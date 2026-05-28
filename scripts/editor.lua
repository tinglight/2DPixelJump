-- ====================================================================
-- LevelEditor.lua - 火焰像素平台跳跃 关卡编辑器（含试玩模式）
-- ====================================================================
--
-- 【工具列表】:
-- 1. 碰撞方块 (SOLID)
-- 2. 主角出生点 (SPAWN)
-- 3. 回复火焰点 (FUEL)
-- 4. 终点门 (GOAL)
-- 5. 刺陷阱 (SPIKE)
-- 6. 开关 (SWITCH) - 带颜色分组
-- 7. 开关控制门 (GATE) - 与同色开关关联
--
-- 【编辑操作】:
-- 鼠标左键：放置  |  鼠标右键：擦除
-- 滚轮：缩放  |  WASD：移动视窗  |  1~7：选工具  |  G：换组色
-- 拖拽边界边缘：扩展摄像机边界（默认20x20格）
-- Z：撤销（绘制操作3秒内合并为一步）
-- Ctrl+S：保存  |  Ctrl+L：加载  |  自动保存（每步操作后延迟1秒）
-- P：进入试玩  |  ESC：退出编辑器
--
-- 【试玩操作】:
-- AD/方向键：移动  |  空格/W：跳跃
-- ESC：返回编辑器
--
-- ====================================================================

require "urhox-libs.UI.VirtualControls"
local LevelGenerator = require "LevelGenerator"
local CloudStorage = require "CloudStorage"
local WorldMapEditor = require "WorldMapEditor"
local FogOfWar = require "FogOfWar"

-- ====================================================================
-- 常量
-- ====================================================================
local GRID = 16
local DESIGN_W = 480
local DESIGN_H = 272
local MAP_COLS = 60
local MAP_ROWS = 17

local TOPBAR_H = 22
local BOTTOMBAR_H = 56   -- 底部工具栏+状态栏
local SIDEBAR_W = 100    -- 右侧关卡列表侧边栏宽度
AUTO_SAVE_DELAY = 1.0    -- 自动保存延时（秒）

-- ====================================================================
-- 地块类型
-- ====================================================================
local TILE = {
    EMPTY       = 0,
    SOLID       = 1,
    SPAWN       = 2,
    FUEL        = 3,
    GOAL        = 4,
    SPIKE       = 5,
    SWITCH      = 6,
    GATE        = 7,
    HIDDEN_WALL = 8,
}

-- 工具分组定义（颜色用于底部工具栏的分组色带标识）
local TOOL_GROUPS = {
    { id = "terrain",  name = "地形",  color = {80, 130, 180} },   -- 蓝灰
    { id = "player",   name = "角色",  color = {255, 200, 50} },   -- 金黄
    { id = "trap",     name = "陷阱",  color = {220, 60, 60} },    -- 红色
    { id = "puzzle",   name = "机关",  color = {130, 80, 220} },   -- 紫色
    { id = "pickup",   name = "补给",  color = {60, 200, 100} },   -- 绿色
}

local TOOLS = {
    { id = "SOLID",       tile = TILE.SOLID,       name = "碰撞", color = {80, 90, 100, 255},  group = "terrain" },
    { id = "SPAWN",       tile = TILE.SPAWN,       name = "主角", color = {255, 200, 50, 255}, group = "player" },
    { id = "FUEL",        tile = TILE.FUEL,        name = "火焰", color = {255, 100, 20, 255}, group = "pickup" },
    { id = "GOAL",        tile = TILE.GOAL,        name = "终点", color = {100, 255, 100, 255}, group = "pickup" },
    { id = "SPIKE",       tile = TILE.SPIKE,       name = "刺",   color = {255, 50, 50, 255},  group = "trap" },
    { id = "SWITCH",      tile = TILE.SWITCH,      name = "开关", color = {200, 200, 50, 255}, group = "puzzle" },
    { id = "GATE",        tile = TILE.GATE,        name = "门",   color = {150, 100, 200, 255}, group = "puzzle" },
    { id = "HIDDEN_WALL", tile = TILE.HIDDEN_WALL, name = "隐墙", color = {100, 180, 200, 255}, group = "puzzle" },
    { id = "LIGHT",       tile = -1,               name = "光源", color = {255, 220, 80, 255},  group = "terrain" },
}

-- 辅助：获取工具所属分组的颜色
local function GetToolGroupColor(tool)
    for _, g in ipairs(TOOL_GROUPS) do
        if g.id == tool.group then return g.color end
    end
    return {100, 100, 100}
end

local GROUP_COLORS = {
    [1] = { 220, 60, 60 },
    [2] = { 60, 120, 220 },
    [3] = { 60, 200, 60 },
    [4] = { 220, 180, 40 },
}
local GROUP_NAMES = { "红", "蓝", "绿", "黄" }
local MAX_GROUPS = 4

-- ====================================================================
-- 编辑器状态
-- ====================================================================
local MODE_EDIT, MODE_PLAY, MODE_WORLDMAP, MODE_WORLDPLAY = 1, 2, 3, 4
local editorMode = MODE_EDIT

local vg = nil
local physW, physH, dpr, logicalW, logicalH
local scaleF, screenDesignW, screenDesignH

local levelData = {}
local currentTool = 1
local currentGroup = 1
local cameraX = 0

-- 隐藏墙分组系统（合并为一个table节省local变量额度）
local hiddenWall = {
    group = 1,                          -- 当前隐藏墙组号
    lastEditTime = 0,                   -- 上次编辑隐藏墙的时间
    timeout = 5.0,                      -- 5秒超时自动切换组号
    prevTool = 0,                       -- 记录上次工具，用于检测切换回来
    baseColor = { 80, 200, 220 },       -- 基础青色
}

local isDrawing = false
local isErasing = false
local lastPlacedCol = -1
local lastPlacedRow = -1

-- ====================================================================
-- 关卡视口状态缓存（切换关卡时保留缩放/位置）
-- ====================================================================
local viewportCache = {}  -- { ["level_1.json"] = { cameraX, cameraY, zoomLevel }, ... }

-- ====================================================================
-- 撤销系统（Undo）
-- ====================================================================
local undo = {
    stack = {},                   -- 操作历史栈
    maxHistory = 200,             -- 最大历史记录数
    drawMergeTime = 3.0,          -- 绘制操作3秒内合并为一步
    currentAction = nil,          -- 当前正在进行的绘制动作（合并用）
    lastTime = 0,                 -- 上次操作时间戳
    dirty = false,                -- 地图是否有未保存的修改
    saveTimer = 0,                -- 自动保存延时
    saveDelay = 1.0,              -- 操作后1秒触发自动保存
}

--- 记录一个地块变更到当前操作中
local function RecordTileChange(col, row, oldVal, newVal)
    if oldVal == newVal then return end
    local now = os.clock()

    -- 判断是否应该合并到当前绘制动作
    if undo.currentAction and (isDrawing or isErasing) and (now - undo.currentAction.timestamp) < undo.drawMergeTime then
        -- 合并到当前绘制动作
        table.insert(undo.currentAction.deltas, { col = col, row = row, oldVal = oldVal, newVal = newVal })
        undo.currentAction.lastTime = now
    else
        -- 创建新的操作记录
        local action = {
            deltas = { { col = col, row = row, oldVal = oldVal, newVal = newVal } },
            timestamp = now,
            lastTime = now,
            actionType = (isDrawing or isErasing) and "draw" or "single",
        }
        table.insert(undo.stack, action)
        if #undo.stack > undo.maxHistory then
            table.remove(undo.stack, 1)
        end
        -- 如果是绘制操作，设为当前绘制动作以便后续合并
        if isDrawing or isErasing then
            undo.currentAction = action
        end
    end

    undo.dirty = true
    undo.saveTimer = undo.saveDelay
    undo.lastTime = now
end

--- 记录一次 spawn 变更（特殊处理：清除旧 spawn + 设置新 spawn）
local function RecordSpawnChange(oldCol, oldRow, newCol, newRow)
    if oldCol == newCol and oldRow == newRow then return end
    local action = {
        deltas = {},
        timestamp = os.clock(),
        lastTime = os.clock(),
        actionType = "spawn",
        spawnChange = { oldCol = oldCol, oldRow = oldRow, newCol = newCol, newRow = newRow },
    }
    -- 记录旧 spawn 位置清除
    if oldCol >= 1 and oldCol <= MAP_COLS and oldRow >= 1 and oldRow <= MAP_ROWS then
        table.insert(action.deltas, { col = oldCol, row = oldRow, oldVal = TILE.SPAWN, newVal = TILE.EMPTY })
    end
    -- 记录新 spawn 位置
    table.insert(action.deltas, { col = newCol, row = newRow, oldVal = TILE.EMPTY, newVal = TILE.SPAWN })
    table.insert(undo.stack, action)
    if #undo.stack > undo.maxHistory then
        table.remove(undo.stack, 1)
    end
    undo.dirty = true
    undo.saveTimer = undo.saveDelay
end

--- 执行撤销
local function Undo()
    if #undo.stack == 0 then
        msgText = "无可撤销操作"
        msgTimer = 1.5
        return
    end
    local action = table.remove(undo.stack)
    -- 逆序恢复所有 delta
    for i = #action.deltas, 1, -1 do
        local d = action.deltas[i]
        levelData[d.row][d.col] = d.oldVal
    end
    -- 恢复 spawn 位置
    if action.spawnChange then
        spawnCol = action.spawnChange.oldCol
        spawnRow = action.spawnChange.oldRow
    else
        -- 检查恢复的格子里是否有 SPAWN，更新 spawnCol/spawnRow
        for i = #action.deltas, 1, -1 do
            local d = action.deltas[i]
            if d.oldVal == TILE.SPAWN then
                spawnCol = d.col
                spawnRow = d.row
            end
        end
    end
    local count = #action.deltas
    msgText = "撤销 (" .. count .. " 格)"
    msgTimer = 1.5
    undo.dirty = true
    undo.saveTimer = undo.saveDelay
end

--- 结束当前绘制动作的合并（鼠标抬起时调用）
local function FinalizeDrawAction()
    undo.currentAction = nil
end

--- 自动保存 / 切换前保存（前向声明，实际实现在 SaveLevel 之后）
local TryAutoSave
local AutoSaveBeforeSwitch

local spawnCol = 3
local spawnRow = MAP_ROWS - 3

local msgText = ""
local msgTimer = 0

-- 随机关卡难度
local DIFFICULTIES = { "easy", "normal", "hard" }
local DIFFICULTY_NAMES = { easy = "简单", normal = "普通", hard = "困难" }
local currentDifficulty = 1  -- 索引: 1=easy, 2=normal, 3=hard

-- 侧边栏状态
local sidebarOpen = true
local savedLevels = {}        -- { {name="level_1", file="level_1.json"}, ... }
local sidebarScroll = 0

-- 对话框状态
local dialogMode = nil        -- nil, "rename", "delete", "canvas"
local dialogTarget = nil      -- 目标关卡 { name, file, index }
local renameInput = ""        -- 重命名输入框内容
local renameCursor = 0        -- 光标位置（字节）
local renameBlink = 0         -- 光标闪烁计时器

-- 画布大小对话框状态
local canvasWidthInput = ""   -- 宽度输入内容
local canvasHeightInput = ""  -- 高度输入内容
local canvasFocusField = 1    -- 1=宽度, 2=高度
local canvasCursor = 0        -- 当前焦点字段的光标位置

-- 玩家参数（每关卡独立）
local playerParams = {
    baseJumpGrids = 3,        -- 满血时的跳跃高度（格）
    fallJumpMultiplier = 1.0, -- 每下落1格增加的跳跃高度倍率
    maxFallGrids = 10,        -- 总共能下落多少格（超过则死亡）
    maxJumpGrids = 8,         -- 最大跳跃高度（格）
}

-- 玩家参数对话框状态
local playerParamInputs = {"3", "1.0", "10", "8"}  -- 4个输入字段内容
local playerParamFocus = 1    -- 当前焦点字段 1~4
local playerParamCursor = 0   -- 当前焦点字段光标位置
local PLAYER_PARAM_LABELS = {"满血跳跃(格)", "下落倍率", "最大下落(格)", "最大跳跃(格)"}
local PLAYER_PARAM_KEYS = {"baseJumpGrids", "fallJumpMultiplier", "maxFallGrids", "maxJumpGrids"}

-- ====================================================================
-- 战争迷雾 & 光源状态
-- ====================================================================
local fogShowInEditor = false      -- 编辑器模式下是否显示迷雾（默认隐藏）
local lightSources = {}            -- 光源数据 { {col, row, diameter, feather}, ... }
local selectedLightIndex = 0       -- 当前选中的光源索引（0=无选中）
local LIGHT_TOOL_INDEX = 8         -- 光源工具在 TOOLS 中的索引

-- 光源配置对话框
local lightDialogOpen = false      -- 光源参数对话框是否打开
local lightDiameterInput = "6"     -- 直径输入
local lightFeatherInput = "0.5"    -- 羽化输入
local lightDialogFocus = 1         -- 焦点字段 1=直径, 2=羽化
local lightDialogCursor = 0        -- 光标位置

-- ====================================================================
-- 编辑器交互模式（选取/移动）
-- ====================================================================
local INTERACT_DRAW = 1      -- 默认绘制模式（放置/擦除地块）
local INTERACT_SELECT = 2    -- 选取模式（点击选中机关单位）
local INTERACT_MOVE = 3      -- 移动模式（拖拽移动选中物体）

local interactMode = INTERACT_DRAW       -- 当前交互模式
local selectedTileCol = 0                -- 选中的地块列（0=无选中）
local selectedTileRow = 0                -- 选中的地块行（0=无选中）
local selectedIsLight = false            -- 选中的是否为光源（不在 levelData 中）

-- 移动拖拽状态
local moveDragging = false               -- 是否正在拖拽移动
local moveDragStartCol = 0               -- 拖拽起始格列
local moveDragStartRow = 0               -- 拖拽起始格行
local moveDragCurrentCol = 0             -- 拖拽当前格列
local moveDragCurrentRow = 0             -- 拖拽当前格行
local moveDragTileValue = 0              -- 拖拽中的地块值
local moveDragLightIdx = 0               -- 拖拽中的光源索引（如果是光源）
local multiMoving = false                -- 是否多选拖拽移动

-- 框选状态
local boxSelectActive = false            -- 是否正在框选
local boxSelectStartX = 0                -- 框选起始屏幕坐标 X
local boxSelectStartY = 0                -- 框选起始屏幕坐标 Y
local boxSelectCurrentX = 0              -- 框选当前屏幕坐标 X
local boxSelectCurrentY = 0              -- 框选当前屏幕坐标 Y
local boxSelectThreshold = 4             -- 拖拽超过此像素才视为框选（区分点击）

-- 多选列表：{ {col=, row=, isLight=, lightIdx=}, ... }
local selectedTiles = {}

--- 判断一个地块是否可选取（非碰撞、非空、非边界）
local function IsTileSelectable(col, row)
    if col < 1 or col > MAP_COLS or row < 1 or row > MAP_ROWS then return false end
    local val = levelData[row][col]
    if val == TILE.EMPTY or val == TILE.SOLID then return false end
    return true
end

--- 清除当前选中
local function ClearSelection()
    selectedTileCol = 0
    selectedTileRow = 0
    selectedIsLight = false
    selectedTiles = {}
    boxSelectActive = false
end

-- ====================================================================
-- 缩放与相机 Y 轴
-- ====================================================================
local zoomLevel = 1.0          -- 编辑器缩放等级（1.0=100%）
local ZOOM_MIN = 0.25
local ZOOM_MAX = 4.0
local ZOOM_FACTOR = 1.25       -- 每次滚轮缩放 25%（乘/除此系数）
local cameraY = 0              -- 相机 Y 偏移（像素，设计坐标）

-- ====================================================================
-- 摄像机边界（可拖拽扩展）
-- ====================================================================
local CAM_BOUND_DEFAULT = 20   -- 默认 20x20 格边界
local camBound = {
    left = 1,
    top = 1,
    right = CAM_BOUND_DEFAULT,
    bottom = CAM_BOUND_DEFAULT,
}

-- 边界拖拽状态
local BOUND_EDGE_NONE, BOUND_EDGE_LEFT, BOUND_EDGE_RIGHT, BOUND_EDGE_TOP, BOUND_EDGE_BOTTOM = 0, 1, 2, 3, 4
local boundDragEdge = BOUND_EDGE_NONE
local boundDragActive = false
local BOUND_DRAG_THRESHOLD = 6  -- 鼠标离边界多少像素内可拖拽

-- ====================================================================
-- 地块工具函数
-- ====================================================================
local function GetTileType(value)
    if not value then return TILE.EMPTY, 0 end
    if value >= 100 then
        return value % 100, math.floor(value / 100)
    end
    return value, 0
end

local function MakeTileValue(baseType, group)
    if (baseType == TILE.SWITCH or baseType == TILE.GATE or baseType == TILE.HIDDEN_WALL) and group > 0 then
        return group * 100 + baseType
    end
    return baseType
end

-- ====================================================================
-- 画布大小调整
-- ====================================================================
local function ResizeCanvas(newCols, newRows)
    -- 限制范围
    newCols = math.max(10, math.min(200, newCols))
    newRows = math.max(5, math.min(100, newRows))

    local oldCols = MAP_COLS
    local oldRows = MAP_ROWS

    -- 创建新地图数据
    local newData = {}
    for row = 1, newRows do
        newData[row] = {}
        for col = 1, newCols do
            if row <= oldRows and col <= oldCols then
                newData[row][col] = levelData[row][col]
            else
                newData[row][col] = TILE.EMPTY
            end
        end
    end

    -- 更新全局变量
    MAP_COLS = newCols
    MAP_ROWS = newRows
    levelData = newData

    -- 确保出生点在新范围内
    if spawnCol > MAP_COLS then spawnCol = MAP_COLS end
    if spawnRow > MAP_ROWS then spawnRow = MAP_ROWS end

    -- 调整摄像机边界
    if camBound.right > MAP_COLS then camBound.right = MAP_COLS end
    if camBound.bottom > MAP_ROWS then camBound.bottom = MAP_ROWS end
    if camBound.left > camBound.right then camBound.left = 1 end
    if camBound.top > camBound.bottom then camBound.top = 1 end

    msgText = "画布大小: " .. MAP_COLS .. "x" .. MAP_ROWS
    msgTimer = 2.0
end

local function OpenCanvasDialog()
    dialogMode = "canvas"
    canvasWidthInput = tostring(MAP_COLS)
    canvasHeightInput = tostring(MAP_ROWS)
    canvasFocusField = 1
    canvasCursor = #canvasWidthInput
    renameBlink = 0
end

local function OpenPlayerDialog()
    dialogMode = "player"
    playerParamInputs[1] = tostring(playerParams.baseJumpGrids)
    playerParamInputs[2] = tostring(playerParams.fallJumpMultiplier)
    playerParamInputs[3] = tostring(playerParams.maxFallGrids)
    playerParamInputs[4] = tostring(playerParams.maxJumpGrids)
    playerParamFocus = 1
    playerParamCursor = #playerParamInputs[1]
    renameBlink = 0
end

local function ApplyPlayerParams()
    local v1 = tonumber(playerParamInputs[1])
    local v2 = tonumber(playerParamInputs[2])
    local v3 = tonumber(playerParamInputs[3])
    local v4 = tonumber(playerParamInputs[4])
    playerParams.baseJumpGrids = math.max(0, math.min(20, v1 or 3))
    playerParams.fallJumpMultiplier = math.max(0, math.min(5.0, v2 or 1.0))
    playerParams.maxFallGrids = math.max(1, math.min(50, v3 or 10))
    playerParams.maxJumpGrids = math.max(1, math.min(30, v4 or 8))
    msgText = "玩家参数已更新"
    msgTimer = 2.0
    undo.dirty = true
end

-- ====================================================================
-- 地图初始化
-- ====================================================================
local function InitEmptyMap()
    for row = 1, MAP_ROWS do
        levelData[row] = {}
        for col = 1, MAP_COLS do
            levelData[row][col] = TILE.EMPTY
        end
    end
    for col = 1, MAP_COLS do
        levelData[MAP_ROWS][col] = TILE.SOLID
        levelData[MAP_ROWS - 1][col] = TILE.SOLID
    end
    spawnCol = 3
    spawnRow = MAP_ROWS - 3
    -- 清空光源
    FogOfWar.ClearAll()
    lightSources = FogOfWar.GetLightSources()
    selectedLightIndex = 0
end

-- ====================================================================
-- 放置/擦除
-- ====================================================================
local function PlaceTile(col, row)
    if col < 1 or col > MAP_COLS or row < 1 or row > MAP_ROWS then return end
    local tool = TOOLS[currentTool]
    local tileType = tool.tile

    if tileType == TILE.SPAWN then
        local oldSpawnCol, oldSpawnRow = spawnCol, spawnRow
        for r = 1, MAP_ROWS do
            for c = 1, MAP_COLS do
                if levelData[r][c] == TILE.SPAWN then
                    levelData[r][c] = TILE.EMPTY
                end
            end
        end
        spawnCol = col
        spawnRow = row
        levelData[row][col] = TILE.SPAWN
        RecordSpawnChange(oldSpawnCol, oldSpawnRow, col, row)
    elseif tileType == TILE.SWITCH or tileType == TILE.GATE then
        local oldVal = levelData[row][col]
        local newVal = MakeTileValue(tileType, currentGroup)
        levelData[row][col] = newVal
        RecordTileChange(col, row, oldVal, newVal)
    elseif tileType == TILE.HIDDEN_WALL then
        -- 隐藏墙不能和碰撞方块共存
        local oldVal = levelData[row][col]
        local oldBase = GetTileType(oldVal)
        if oldBase == TILE.SOLID then return end  -- 不能覆盖碰撞方块
        -- 5秒分组逻辑
        local now = os.clock()
        if (now - hiddenWall.lastEditTime) > hiddenWall.timeout then
            hiddenWall.group = hiddenWall.group + 1
        end
        hiddenWall.lastEditTime = now
        local newVal = MakeTileValue(TILE.HIDDEN_WALL, hiddenWall.group)
        levelData[row][col] = newVal
        RecordTileChange(col, row, oldVal, newVal)
    else
        local oldVal = levelData[row][col]
        -- 碰撞方块不能覆盖隐藏墙
        if tileType == TILE.SOLID then
            local oldBase = GetTileType(oldVal)
            if oldBase == TILE.HIDDEN_WALL then return end
        end
        levelData[row][col] = tileType
        RecordTileChange(col, row, oldVal, tileType)
    end
end

local function EraseTile(col, row)
    if col < 1 or col > MAP_COLS or row < 1 or row > MAP_ROWS then return end
    if levelData[row][col] == TILE.SPAWN then return end
    local oldVal = levelData[row][col]
    levelData[row][col] = TILE.EMPTY
    RecordTileChange(col, row, oldVal, TILE.EMPTY)
end

-- ====================================================================
-- 保存/加载（多关卡支持）
-- ====================================================================

--- 从关卡文件中读取自定义名称
local function ReadLevelDisplayName(fname, defaultName)
    local json = CloudStorage.Load(fname)
    if not json then return defaultName end
    local ok, data = pcall(cjson.decode, json)
    if ok and data and data.levelName and data.levelName ~= "" then
        return data.levelName
    end
    return defaultName
end

--- 刷新已保存关卡列表
local function RefreshSavedLevels()
    savedLevels = {}
    local files = CloudStorage.ListLevels()
    for _, fname in ipairs(files) do
        local idx = tonumber(fname:match("level_(%d+)%.json")) or 0
        local defaultName = idx > 0 and ("关卡 " .. idx) or "关卡 (旧)"
        local displayName = ReadLevelDisplayName(fname, defaultName)
        table.insert(savedLevels, { name = displayName, file = fname, index = idx })
    end
end

--- 获取下一个可用的关卡编号
local function GetNextLevelIndex()
    return CloudStorage.GetNextIndex()
end

SaveLevel = function()
    local data = {
        cols = MAP_COLS, rows = MAP_ROWS,
        spawn = { col = spawnCol, row = spawnRow },
        tiles = {},
        camBound = {
            left = camBound.left,
            top = camBound.top,
            right = camBound.right,
            bottom = camBound.bottom,
        },
        playerParams = {
            baseJumpGrids = playerParams.baseJumpGrids,
            fallJumpMultiplier = playerParams.fallJumpMultiplier,
            maxFallGrids = playerParams.maxFallGrids,
            maxJumpGrids = playerParams.maxJumpGrids,
        },
        lightSources = FogOfWar.Serialize(),
    }
    for row = 1, MAP_ROWS do
        for col = 1, MAP_COLS do
            local v = levelData[row][col]
            if v ~= TILE.EMPTY and v ~= TILE.SPAWN then
                table.insert(data.tiles, { col = col, row = row, v = v })
            end
        end
    end
    local json = cjson.encode(data)

    -- 确定文件名
    local fname
    if currentLevelName and currentLevelName ~= "" then
        fname = currentLevelName
    else
        local idx = GetNextLevelIndex()
        fname = "level_" .. idx .. ".json"
        currentLevelName = fname
    end

    msgText = "正在保存..."
    msgTimer = 5.0
    CloudStorage.Save(fname, json, function(ok, err)
        if ok then
            msgText = "已保存: " .. fname .. " (" .. #data.tiles .. " 块)"
            msgTimer = 3.0
            RefreshSavedLevels()
        else
            msgText = "保存失败: " .. (err or "未知错误")
            msgTimer = 3.0
        end
    end)
end

--- 自动保存实现（延迟触发，避免频繁写入）
TryAutoSave = function()
    if undo.dirty and currentLevelName and currentLevelName ~= "" then
        SaveLevel()
        undo.dirty = false
    end
end

--- 切换关卡/模式前自动保存实现
AutoSaveBeforeSwitch = function()
    -- 保存当前关卡的视口状态
    if currentLevelName and currentLevelName ~= "" then
        viewportCache[currentLevelName] = {
            cameraX = cameraX,
            cameraY = cameraY,
            zoomLevel = zoomLevel,
        }
    end
    if undo.dirty and currentLevelName and currentLevelName ~= "" then
        SaveLevel()
        undo.dirty = false
    end
    -- 切换时清空 undo 历史
    undo.stack = {}
    undo.currentAction = nil
end

--- 保存为新关卡（始终创建新文件）
local function SaveAsNewLevel()
    currentLevelName = ""  -- 清空当前名，SaveLevel 会自动分配新编号
    SaveLevel()
end

local function LoadLevel(filename)
    local fname = filename or "level.json"
    local json = CloudStorage.Load(fname)
    if not json then
        msgText = "未找到: " .. fname
        msgTimer = 3.0
        return
    end
    local ok, data = pcall(cjson.decode, json)
    if not ok or not data then
        msgText = "解析失败!"
        msgTimer = 3.0
        return
    end
    -- 恢复画布大小
    if data.cols and data.cols >= 10 then MAP_COLS = data.cols end
    if data.rows and data.rows >= 5 then MAP_ROWS = data.rows end

    -- 重建 levelData
    levelData = {}
    for row = 1, MAP_ROWS do
        levelData[row] = {}
        for col = 1, MAP_COLS do
            levelData[row][col] = TILE.EMPTY
        end
    end
    if data.spawn then
        spawnCol = data.spawn.col or 3
        spawnRow = data.spawn.row or (MAP_ROWS - 3)
        levelData[spawnRow][spawnCol] = TILE.SPAWN
    end
    if data.tiles then
        for _, t in ipairs(data.tiles) do
            if t.row >= 1 and t.row <= MAP_ROWS and t.col >= 1 and t.col <= MAP_COLS then
                levelData[t.row][t.col] = t.v
            end
        end
    end
    -- 恢复摄像机边界
    if data.camBound then
        camBound.left = data.camBound.left or 1
        camBound.top = data.camBound.top or 1
        camBound.right = data.camBound.right or CAM_BOUND_DEFAULT
        camBound.bottom = data.camBound.bottom or CAM_BOUND_DEFAULT
    else
        camBound.left = 1
        camBound.top = 1
        camBound.right = CAM_BOUND_DEFAULT
        camBound.bottom = CAM_BOUND_DEFAULT
    end
    -- 恢复玩家参数
    if data.playerParams then
        playerParams.baseJumpGrids = data.playerParams.baseJumpGrids or 3
        playerParams.fallJumpMultiplier = data.playerParams.fallJumpMultiplier or 1.0
        playerParams.maxFallGrids = data.playerParams.maxFallGrids or 10
        playerParams.maxJumpGrids = data.playerParams.maxJumpGrids or 8
    else
        playerParams.baseJumpGrids = 3
        playerParams.fallJumpMultiplier = 1.0
        playerParams.maxFallGrids = 10
        playerParams.maxJumpGrids = 8
    end
    -- 恢复光源数据
    FogOfWar.Deserialize(data.lightSources)
    lightSources = FogOfWar.GetLightSources()
    selectedLightIndex = 0

    currentLevelName = fname
    -- 恢复该关卡的视口状态（如有缓存），否则使用默认值
    local cached = viewportCache[fname]
    if cached then
        cameraX = cached.cameraX
        cameraY = cached.cameraY
        zoomLevel = cached.zoomLevel
    else
        cameraX = 0
        cameraY = 0
        zoomLevel = 1.0
    end
    -- 加载后重置 undo 状态
    undo.stack = {}
    undo.currentAction = nil
    undo.dirty = false
    undo.saveTimer = 0
    msgText = "已加载: " .. fname
    msgTimer = 2.0
end

--- 重命名关卡文件
local function RenameLevel(oldFile, newDisplayName)
    local json = CloudStorage.Load(oldFile)
    if not json then
        msgText = "文件不存在: " .. oldFile
        msgTimer = 3.0
        return
    end
    local ok, data = pcall(cjson.decode, json)
    if not ok or not data then
        msgText = "解析失败!"
        msgTimer = 3.0
        return
    end
    -- 写入自定义名称
    data.levelName = newDisplayName
    local newJson = cjson.encode(data)
    CloudStorage.Save(oldFile, newJson, function(saveOk, err)
        if saveOk then
            msgText = "已重命名: " .. newDisplayName
            msgTimer = 2.0
            RefreshSavedLevels()
        else
            msgText = "重命名失败: " .. (err or "未知错误")
            msgTimer = 3.0
        end
    end)
end

--- 删除关卡文件
local function DeleteLevel(filename)
    if not CloudStorage.Exists(filename) then
        msgText = "文件不存在!"
        msgTimer = 3.0
        return
    end
    CloudStorage.Delete(filename, function(ok, err)
        if ok then
            msgText = "已删除: " .. filename
            msgTimer = 2.0
            if currentLevelName == filename then
                currentLevelName = ""
            end
            RefreshSavedLevels()
        else
            msgText = "删除失败: " .. (err or "未知错误")
            msgTimer = 3.0
        end
    end)
end

-- ====================================================================
-- 坐标转换
-- ====================================================================
local function ScreenToGrid(sx, sy)
    local localX = (sx + cameraX) / zoomLevel
    local localY = (sy - TOPBAR_H + cameraY) / zoomLevel
    return math.floor(localX / GRID) + 1, math.floor(localY / GRID) + 1
end

--- 将网格坐标转为屏幕坐标（用于边界绘制等）
local function GridToScreen(col, row)
    local sx = (col - 1) * GRID * zoomLevel - cameraX
    local sy = (row - 1) * GRID * zoomLevel - cameraY + TOPBAR_H
    return sx, sy
end

--- 检测鼠标是否在摄像机边界的某条边附近，返回边 ID
local function DetectBoundEdge(mx, my)
    local mapY = TOPBAR_H
    local mapW = screenDesignW - (sidebarOpen and SIDEBAR_W or 0)
    local mapH = screenDesignH - TOPBAR_H - BOTTOMBAR_H
    -- 鼠标不在地图区域内则不检测
    if mx < 0 or mx > mapW or my < mapY or my > mapY + mapH then
        return BOUND_EDGE_NONE
    end

    local leftX, leftY = GridToScreen(camBound.left, camBound.top)
    local rightX, rightY = GridToScreen(camBound.right + 1, camBound.bottom + 1)

    local threshold = BOUND_DRAG_THRESHOLD

    -- 右边
    if math.abs(mx - rightX) < threshold and my >= leftY and my <= rightY then
        return BOUND_EDGE_RIGHT
    end
    -- 左边
    if math.abs(mx - leftX) < threshold and my >= leftY and my <= rightY then
        return BOUND_EDGE_LEFT
    end
    -- 下边
    if math.abs(my - rightY) < threshold and mx >= leftX and mx <= rightX then
        return BOUND_EDGE_BOTTOM
    end
    -- 上边
    if math.abs(my - leftY) < threshold and mx >= leftX and mx <= rightX then
        return BOUND_EDGE_TOP
    end

    return BOUND_EDGE_NONE
end

-- ====================================================================
-- 随机关卡生成（使用 LevelGenerator 模块）
-- ====================================================================

--- 生成随机关卡（围绕火焰核心机制）
local function GenerateRandomLevel()
    local diff = DIFFICULTIES[currentDifficulty]
    local map, sc, sr, templateName = LevelGenerator.GenerateValid(diff, 5)

    -- 将生成的地图数据写入 levelData
    -- LevelGenerator 固定输出 60x17，editor 的 MAP_ROWS/MAP_COLS 可能不同
    for row = 1, MAP_ROWS do
        levelData[row] = {}
        for col = 1, MAP_COLS do
            if row <= LevelGenerator.MAP_ROWS and col <= LevelGenerator.MAP_COLS then
                levelData[row][col] = map[row][col]
            else
                levelData[row][col] = TILE.EMPTY
            end
        end
    end

    spawnCol = sc
    spawnRow = sr

    -- 更新摄像机边界为整个地图范围
    camBound.left = 1
    camBound.top = 1
    camBound.right = MAP_COLS
    camBound.bottom = MAP_ROWS

    -- 重置编辑器相机
    cameraX = 0
    currentLevelName = ""

    -- 重置 undo 状态（随机生成是全新地图）
    undo.stack = {}
    undo.currentAction = nil
    undo.dirty = false
    undo.saveTimer = 0

    -- 清空光源
    FogOfWar.ClearAll()
    lightSources = FogOfWar.GetLightSources()
    selectedLightIndex = 0

    local diffName = DIFFICULTY_NAMES[diff] or diff
    msgText = "随机[" .. diffName .. "] 模板:" .. templateName
    msgTimer = 4.0
end

--- 切换随机关卡难度
local function CycleDifficulty()
    currentDifficulty = currentDifficulty % #DIFFICULTIES + 1
    local diff = DIFFICULTIES[currentDifficulty]
    local diffName = DIFFICULTY_NAMES[diff]
    msgText = "难度: " .. diffName
    msgTimer = 2.0
end

-- ====================================================================
-- 试玩模式 (PLAY MODE) - 完整火焰渲染
-- ====================================================================

-- 火焰形状定义（10x10 像素点阵，尖顶宽底）
local CHAR_SHAPE = {
    { 0, 0, 0, 0, 1, 1, 0, 0, 0, 0 },
    { 0, 0, 0, 1, 1, 1, 1, 0, 0, 0 },
    { 0, 0, 1, 1, 1, 1, 1, 1, 0, 0 },
    { 0, 0, 1, 1, 1, 1, 1, 1, 0, 0 },
    { 0, 1, 1, 1, 1, 1, 1, 1, 1, 0 },
    { 0, 1, 1, 1, 1, 1, 1, 1, 1, 0 },
    { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
    { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
    { 0, 1, 1, 1, 1, 1, 1, 1, 1, 0 },
    { 0, 0, 1, 1, 1, 1, 1, 1, 0, 0 },
}

-- 火焰渐变色：白芯→黄→橙→红→深红
local FLAME_COLORS = {
    [1]  = { 255, 255, 220 },
    [2]  = { 255, 240, 150 },
    [3]  = { 255, 220, 80 },
    [4]  = { 255, 200, 50 },
    [5]  = { 255, 160, 30 },
    [6]  = { 255, 130, 20 },
    [7]  = { 240, 90, 10 },
    [8]  = { 220, 60, 5 },
    [9]  = { 200, 40, 5 },
    [10] = { 160, 20, 5 },
}

-- 火焰配置
local FLAME_CFG = {
    pixelGridSize = 10,
    pixelSize = 3,
    flickerSpeed = 8.0,
}

-- 火焰动画帧系统
local FLAME_ANIM_FPS = 10
local flameAnimTimer = 0
local flameAnimFrame = 0
local rowOffsets = {}
local rowVOffsets = {}
local playFallParticles = {}  -- 下落火星粒子 { x, y, vx, vy, life, maxLife, size, gravity, groundY, bounces, maxBounces, colorRow }

local play = {
    gridX = 3, gridY = 10,
    isOnGround = false,
    isJumping = false,
    jumpGridsRemain = 0,
    facingRight = true,
    moveTimer = 0,
    fallTimer = 0,
    fallTickCurrent = 0.12,
    jumpTimer = 0,
    fallGridCount = 0,
    alive = true,
    won = false,
    isMoving = false,
    moveAnimTime = 0,
    fallAnimTime = 0,
    -- 开关状态
    switchState = {},
    collected = {},
    -- 隐藏墙已触发组
    hiddenWallRevealed = {},
}

-- 像素状态
local pixelState = {}
local playTotalPixels = 0
local playAlivePixels = 0
local stripOrder = {}

-- 试玩常量
local PLAY_MOVE_TICK = 0.10
local PLAY_FALL_BASE = 0.12
local PLAY_FALL_MIN  = 0.04
local PLAY_FALL_ACCEL = 0.015
local PLAY_JUMP_TICK = 0.07
local PLAY_BASE_JUMP = 3
local PLAY_RECOVER_PER_SEC = 6

-- 初始化像素状态
local function InitPlayPixels()
    pixelState = {}
    playTotalPixels = 0
    local N = FLAME_CFG.pixelGridSize
    for row = 1, N do
        pixelState[row] = {}
        for col = 1, N do
            if CHAR_SHAPE[row][col] == 1 then
                pixelState[row][col] = true
                playTotalPixels = playTotalPixels + 1
            else
                pixelState[row][col] = false
            end
        end
    end
    playAlivePixels = playTotalPixels

    -- 剥离顺序：外侧先剥
    stripOrder = {}
    local cx = (N + 1) / 2
    for row = 1, N do
        for col = 1, N do
            if CHAR_SHAPE[row][col] == 1 then
                local hDist = math.abs(col - cx)
                local vWeight = (N - row) * 0.1
                table.insert(stripOrder, { row = row, col = col, priority = hDist + vWeight })
            end
        end
    end
    table.sort(stripOrder, function(a, b) return a.priority > b.priority end)
end

local function PlayStripPixels(n)
    local stripped = 0
    for _, p in ipairs(stripOrder) do
        if stripped >= n then break end
        if pixelState[p.row][p.col] then
            pixelState[p.row][p.col] = false
            playAlivePixels = playAlivePixels - 1
            stripped = stripped + 1
        end
    end
end

local function PlayRecoverPixels(n)
    local recovered = 0
    for i = #stripOrder, 1, -1 do
        if recovered >= n then break end
        local p = stripOrder[i]
        if not pixelState[p.row][p.col] then
            pixelState[p.row][p.col] = true
            playAlivePixels = playAlivePixels + 1
            recovered = recovered + 1
        end
    end
end

-- 更新火焰动画帧
local function UpdatePlayFlameAnim()
    flameAnimFrame = flameAnimFrame + 1
    local N = FLAME_CFG.pixelGridSize

    local maxAmp = 1
    if not play.isOnGround and not play.isJumping then
        maxAmp = 2
    elseif play.isMoving then
        maxAmp = 2
    end

    for row = 1, N do
        local rowFactor = (N - row) / N
        local amp = math.floor(maxAmp * rowFactor + 0.5)
        local phase = flameAnimFrame * 0.7 - row * 0.8
        local rawWave = math.sin(phase)
        local intOffset = math.floor(rawWave * amp + 0.5)

        if play.isMoving then
            local leanDir = play.facingRight and 1 or -1
            local lean = math.floor(rowFactor * 1.5 + 0.5) * leanDir
            intOffset = intOffset + lean
        end

        rowOffsets[row] = intOffset
        rowVOffsets[row] = 0
    end
end

local function PlayIsSolid(col, row)
    if col < 1 or col > MAP_COLS then return true end
    if row < 1 then return false end
    if row > MAP_ROWS then return true end
    local val = levelData[row][col]
    local base, group = GetTileType(val)
    if base == TILE.SOLID then return true end
    -- 门：未激活时视为实体
    if base == TILE.GATE then
        if not play.switchState[group] then return true end
    end
    -- 隐藏墙：未被触发消失时视为实体
    if base == TILE.HIDDEN_WALL then
        if not play.hiddenWallRevealed[group] then return true end
    end
    return false
end

local function PlayPlayerGridSize()
    local totalPx = FLAME_CFG.pixelGridSize * FLAME_CFG.pixelSize
    return math.ceil(totalPx / GRID)
end

local function PlayOnGround(gx, gy)
    local s = PlayPlayerGridSize()
    local feetRow = gy + s
    for dx = 0, s - 1 do
        if PlayIsSolid(gx + dx, feetRow) then return true end
    end
    return false
end

local function PlayCollides(gx, gy)
    local s = PlayPlayerGridSize()
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            if PlayIsSolid(gx + dx, gy + dy) then return true end
        end
    end
    return false
end

local function PlayCheckTiles()
    local s = PlayPlayerGridSize()
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            local col = play.gridX + dx
            local row = play.gridY + dy
            if col >= 1 and col <= MAP_COLS and row >= 1 and row <= MAP_ROWS then
                local val = levelData[row][col]
                local base, group = GetTileType(val)
                local key = row .. "_" .. col

                if base == TILE.SPIKE then
                    play.alive = false
                elseif base == TILE.GOAL then
                    play.won = true
                elseif base == TILE.FUEL and not play.collected[key] then
                    play.collected[key] = true
                    PlayRecoverPixels(math.floor(playTotalPixels * 0.4))
                    local pixelsPerGrid = math.max(1, math.floor(playTotalPixels / 10 + 0.5))
                    play.fallGridCount = math.max(0, math.floor((playTotalPixels - playAlivePixels) / pixelsPerGrid))
                elseif base == TILE.SWITCH and not play.collected[key] then
                    play.collected[key] = true
                    play.switchState[group] = not play.switchState[group]
                elseif base == TILE.HIDDEN_WALL and not play.hiddenWallRevealed[group] then
                    -- 玩家与隐藏墙重叠（正常不会发生，但以防万一）
                    play.hiddenWallRevealed[group] = true
                end
            end
        end
    end
    -- 检测玩家邻近的隐藏墙（玩家紧贴的格子）
    local s2 = PlayPlayerGridSize()
    local gx2, gy2 = play.gridX, play.gridY
    -- 上方一行
    for dx = 0, s2 - 1 do
        local col2, row2 = gx2 + dx, gy2 - 1
        if col2 >= 1 and col2 <= MAP_COLS and row2 >= 1 and row2 <= MAP_ROWS then
            local ab, ag = GetTileType(levelData[row2][col2])
            if ab == TILE.HIDDEN_WALL and not play.hiddenWallRevealed[ag] then
                play.hiddenWallRevealed[ag] = true
            end
        end
    end
    -- 下方一行
    for dx = 0, s2 - 1 do
        local col2, row2 = gx2 + dx, gy2 + s2
        if col2 >= 1 and col2 <= MAP_COLS and row2 >= 1 and row2 <= MAP_ROWS then
            local ab, ag = GetTileType(levelData[row2][col2])
            if ab == TILE.HIDDEN_WALL and not play.hiddenWallRevealed[ag] then
                play.hiddenWallRevealed[ag] = true
            end
        end
    end
    -- 左侧一列
    for dy = 0, s2 - 1 do
        local col2, row2 = gx2 - 1, gy2 + dy
        if col2 >= 1 and col2 <= MAP_COLS and row2 >= 1 and row2 <= MAP_ROWS then
            local ab, ag = GetTileType(levelData[row2][col2])
            if ab == TILE.HIDDEN_WALL and not play.hiddenWallRevealed[ag] then
                play.hiddenWallRevealed[ag] = true
            end
        end
    end
    -- 右侧一列
    for dy = 0, s2 - 1 do
        local col2, row2 = gx2 + s2, gy2 + dy
        if col2 >= 1 and col2 <= MAP_COLS and row2 >= 1 and row2 <= MAP_ROWS then
            local ab, ag = GetTileType(levelData[row2][col2])
            if ab == TILE.HIDDEN_WALL and not play.hiddenWallRevealed[ag] then
                play.hiddenWallRevealed[ag] = true
            end
        end
    end
end



local function PlayCalcJump()
    local baseJump = playerParams.baseJumpGrids
    local bonus = play.fallGridCount * playerParams.fallJumpMultiplier
    return math.min(math.floor(baseJump + bonus + 0.5), playerParams.maxJumpGrids)
end

local prevPlayLeft = false
local prevPlayRight = false
local playMoveFirst = false
local playCameraX = 0
local playGameTime = 0

-- 世界试玩模式状态
local worldPlayData = nil        -- 世界地图数据（节点+连接）
local worldPlayCurrentFile = nil -- 当前关卡文件名
local worldPlayCooldown = 0     -- 切换冷却时间

local function WorldPlayLoadLevel(filename, fromDirection, prevGx, prevGy)
    local json = CloudStorage.Load(filename)
    if not json then return false end
    local ok2, data = pcall(cjson.decode, json)
    if not ok2 or not data then return false end
    -- 清空 levelData
    for row = 1, MAP_ROWS do
        for col = 1, MAP_COLS do
            levelData[row][col] = TILE.EMPTY
        end
    end
    if data.spawn then
        spawnCol = data.spawn.col or 3
        spawnRow = data.spawn.row or (MAP_ROWS - 3)
        levelData[spawnRow][spawnCol] = TILE.SPAWN
    end
    if data.tiles then
        for _, t in ipairs(data.tiles) do
            if t.row >= 1 and t.row <= MAP_ROWS and t.col >= 1 and t.col <= MAP_COLS then
                levelData[t.row][t.col] = t.v
            end
        end
    end
    -- 读取新关卡的摄像机边界
    if data.camBound then
        camBound.left = data.camBound.left or 1
        camBound.top = data.camBound.top or 1
        camBound.right = data.camBound.right or CAM_BOUND_DEFAULT
        camBound.bottom = data.camBound.bottom or CAM_BOUND_DEFAULT
    else
        camBound.left = 1
        camBound.top = 1
        camBound.right = CAM_BOUND_DEFAULT
        camBound.bottom = CAM_BOUND_DEFAULT
    end
    -- 读取新关卡的玩家参数
    if data.playerParams then
        playerParams.baseJumpGrids = data.playerParams.baseJumpGrids or 3
        playerParams.fallJumpMultiplier = data.playerParams.fallJumpMultiplier or 1.0
        playerParams.maxFallGrids = data.playerParams.maxFallGrids or 10
        playerParams.maxJumpGrids = data.playerParams.maxJumpGrids or 8
    else
        playerParams.baseJumpGrids = 3
        playerParams.fallJumpMultiplier = 1.0
        playerParams.maxFallGrids = 10
        playerParams.maxJumpGrids = 8
    end
    -- 加载新关卡的光源数据（修复：切换关卡时光源未清除导致继承上一关光源）
    FogOfWar.Deserialize(data.lightSources)
    lightSources = FogOfWar.GetLightSources()

    worldPlayCurrentFile = filename
    -- 根据进入方向定位玩家到新关卡对应边界
    -- fromDirection = "right" 表示玩家从右侧进入（向左走过来的），应出现在右边界
    -- fromDirection = "left" 表示玩家从左侧进入（向右走过来的），应出现在左边界
    if fromDirection == "right" then
        play.gridX = camBound.right
        play.gridY = prevGy or spawnRow
    elseif fromDirection == "left" then
        play.gridX = camBound.left
        play.gridY = prevGy or spawnRow
    elseif fromDirection == "down" then
        play.gridX = prevGx or spawnCol
        play.gridY = camBound.bottom
    elseif fromDirection == "up" then
        play.gridX = prevGx or spawnCol
        play.gridY = camBound.top
    else
        -- 初始加载，使用出生点
        play.gridX = spawnCol
        play.gridY = spawnRow
    end
    -- 确保玩家位置在有效范围内
    play.gridX = math.max(1, math.min(play.gridX, MAP_COLS))
    play.gridY = math.max(1, math.min(play.gridY, MAP_ROWS))
    -- 相机直接对准玩家，避免切换后突兀的镜头移动
    local boundLeftPx = (camBound.left - 1) * GRID
    local boundRightPx = camBound.right * GRID
    local viewW = DESIGN_W
    local camMinX = boundLeftPx
    local camMaxX = math.max(boundLeftPx, boundRightPx - viewW)
    local targetCam = (play.gridX - 1) * GRID - viewW * 0.35
    playCameraX = math.max(camMinX, math.min(targetCam, camMaxX))
    worldPlayCooldown = 0.5
    return true
end

local function WorldPlayFindConnection(direction)
    if not worldPlayData or not worldPlayCurrentFile then return nil end
    -- 找到当前关卡对应的节点 id
    local currentNodeId = nil
    for _, node in ipairs(worldPlayData.nodes) do
        if node.file == worldPlayCurrentFile then
            currentNodeId = node.id
            break
        end
    end
    if not currentNodeId then return nil end
    -- 在连接中查找方向匹配的
    for _, conn in ipairs(worldPlayData.connections) do
        if conn.fromId == currentNodeId and conn.direction == direction then
            -- 找到目标节点
            for _, node in ipairs(worldPlayData.nodes) do
                if node.id == conn.toId then
                    return node.file
                end
            end
        end
    end
    return nil
end

local function WorldPlayCheckBoundary()
    if worldPlayCooldown > 0 then return end
    local gx, gy = play.gridX, play.gridY
    local dir = nil
    local fromDir = nil
    -- 使用摄像机边界（camBound）作为关卡切换触发线
    local pressLeft = input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)
    local pressRight = input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)
    if gx <= camBound.left and pressLeft then dir = "left"; fromDir = "right"
    elseif gx >= camBound.right and pressRight then dir = "right"; fromDir = "left"
    elseif gy <= camBound.top then dir = "up"; fromDir = "down"
    elseif gy >= camBound.bottom or gy >= MAP_ROWS then dir = "down"; fromDir = "up" end
    if not dir then return end
    local targetFile = WorldPlayFindConnection(dir)
    if targetFile then
        if WorldPlayLoadLevel(targetFile, fromDir, gx, gy) then
            InitPlayPixels()
            msgText = "进入: " .. targetFile
            msgTimer = 1.5
        end
    end
end

local function StartWorldPlayMode()
    worldPlayData = WorldMapEditor.GetMapData()
    if not worldPlayData or not worldPlayData.nodes or #worldPlayData.nodes == 0 then
        msgText = "世界地图为空，请先添加关卡节点"
        msgTimer = 3.0
        return
    end
    -- 加载第一个关卡
    local firstNode = worldPlayData.nodes[1]
    if not firstNode or not firstNode.file then
        msgText = "首个节点无关卡文件"
        msgTimer = 3.0
        return
    end
    if not WorldPlayLoadLevel(firstNode.file, nil) then
        msgText = "加载关卡失败: " .. firstNode.file
        msgTimer = 3.0
        return
    end
    worldPlayCurrentFile = firstNode.file
    worldPlayCooldown = 0
    editorMode = MODE_WORLDPLAY
    -- 初始化玩家状态（复用 StartPlayMode 逻辑）
    play.gridX = spawnCol
    play.gridY = spawnRow
    play.isOnGround = false
    play.isJumping = false
    play.jumpGridsRemain = 0
    play.facingRight = true
    play.moveTimer = 0
    play.fallTimer = 0
    play.fallTickCurrent = PLAY_FALL_BASE
    play.jumpTimer = 0
    play.fallGridCount = 0
    play.alive = true
    play.won = false
    play.isMoving = false
    play.moveAnimTime = 0
    play.fallAnimTime = 0
    play.switchState = {}
    play.collected = {}
    play.hiddenWallRevealed = {}
    prevPlayLeft = false
    prevPlayRight = false
    playMoveFirst = false
    playGameTime = 0
    flameAnimTimer = 0
    flameAnimFrame = 0
    playFallParticles = {}
    playCameraX = math.max(0, (spawnCol - 1) * GRID - DESIGN_W * 0.35)
    InitPlayPixels()
    msgText = "世界试玩中! ESC返回 | 到达边界自动切换关卡"
    msgTimer = 3.0
end

local function StartPlayMode()
    editorMode = MODE_PLAY
    play.gridX = spawnCol
    play.gridY = spawnRow
    play.isOnGround = false
    play.isJumping = false
    play.jumpGridsRemain = 0
    play.facingRight = true
    play.moveTimer = 0
    play.fallTimer = 0
    play.fallTickCurrent = PLAY_FALL_BASE
    play.jumpTimer = 0
    play.fallGridCount = 0
    play.alive = true
    play.won = false
    play.isMoving = false
    play.moveAnimTime = 0
    play.fallAnimTime = 0
    play.switchState = {}
    play.collected = {}
    play.hiddenWallRevealed = {}
    prevPlayLeft = false
    prevPlayRight = false
    playMoveFirst = false
    playGameTime = 0
    flameAnimTimer = 0
    flameAnimFrame = 0
    playFallParticles = {}
    playCameraX = math.max(0, (spawnCol - 1) * GRID - DESIGN_W * 0.35)
    InitPlayPixels()
    msgText = "试玩中! ESC返回编辑"
    msgTimer = 2.0
end

local function PlayMoveOneGrid(dir)
    local newX = play.gridX + dir
    if not PlayCollides(newX, play.gridY) then
        play.gridX = newX
    end
    play.facingRight = (dir > 0)
end

local function PlayUpdate(dt)
    -- 备用ESC检测（防止KeyDown事件被平台拦截）
    if input:GetKeyPress(KEY_ESCAPE) then
        if editorMode == MODE_PLAY then
            editorMode = MODE_EDIT
            msgText = "返回编辑模式"
            msgTimer = 1.5
            return
        elseif editorMode == MODE_WORLDPLAY then
            editorMode = MODE_WORLDMAP
            WorldMapEditor.SetLayout(screenDesignW, screenDesignH, TOPBAR_H, 0, sidebarOpen and SIDEBAR_W or 0)
            msgText = "返回世界地图编辑"
            msgTimer = 1.5
            return
        end
    end

    if not play.alive or play.won then return end

    playGameTime = playGameTime + dt

    -- 火焰动画帧驱动
    flameAnimTimer = flameAnimTimer + dt
    local frameInterval = 1.0 / FLAME_ANIM_FPS
    if flameAnimTimer >= frameInterval then
        flameAnimTimer = flameAnimTimer - frameInterval
        UpdatePlayFlameAnim()
    end

    -- 下落火星粒子更新
    local isFalling = not play.isOnGround and not play.isJumping
    if isFalling and playAlivePixels < playTotalPixels then
        local consumeRatio = 1.0 - playAlivePixels / math.max(1, playTotalPixels)
        local baseRatio = math.max(0.15, consumeRatio)
        local maxParticles = math.floor(4 + baseRatio * 14)
        local spawnChance = 0.40 + baseRatio * 0.50
        local spawnAttempts = 1 + math.floor(baseRatio * 2)

        -- 查找脚下地面
        local playerS = math.ceil(FLAME_CFG.pixelGridSize * FLAME_CFG.pixelSize / GRID)
        local feetGridY = play.gridY + playerS
        local groundGridY = feetGridY
        for searchY = feetGridY, MAP_ROWS do
            if PlayIsSolid(play.gridX, searchY) then
                groundGridY = searchY
                break
            end
            if searchY == MAP_ROWS then groundGridY = MAP_ROWS + 1 end
        end
        local groundY = (groundGridY - 1) * GRID

        local pN = FLAME_CFG.pixelGridSize
        local pPS = FLAME_CFG.pixelSize
        local totalSize = pN * pPS
        for _ = 1, spawnAttempts do
            if math.random() < spawnChance and #playFallParticles < maxParticles then
                local worldX = (play.gridX - 1) * GRID
                local baseY2 = (play.gridY - 1) * GRID
                local side = math.random() > 0.5 and 1 or -1
                local emitX = worldX + totalSize * 0.5 + side * (totalSize * 0.3 + math.random() * totalSize * 0.2)
                local emitY = baseY2 + totalSize * (0.3 + math.random() * 0.5)
                local speedMul = 0.7 + consumeRatio * 0.6
                local life = 1.2 + consumeRatio * 0.6 + math.random() * 0.3
                table.insert(playFallParticles, {
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
        end
    end
    -- 更新已有粒子
    local pi = 1
    while pi <= #playFallParticles do
        local p = playFallParticles[pi]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(playFallParticles, pi)
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
            pi = pi + 1
        end
    end

    -- 输入
    local curLeft = input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)
    local curRight = input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)

    local dir = 0
    if curLeft and not curRight then dir = -1
    elseif curRight and not curLeft then dir = 1 end

    if dir ~= 0 then
        local justPressed = false
        if dir == -1 and not prevPlayLeft then justPressed = true end
        if dir == 1 and not prevPlayRight then justPressed = true end

        if justPressed then
            PlayMoveOneGrid(dir)
            play.moveTimer = 0
            playMoveFirst = true
        else
            play.moveTimer = play.moveTimer + dt
            if play.moveTimer >= PLAY_MOVE_TICK then
                play.moveTimer = play.moveTimer - PLAY_MOVE_TICK
                PlayMoveOneGrid(dir)
            end
        end
        play.isMoving = true
        play.moveAnimTime = play.moveAnimTime + dt
    else
        play.moveTimer = 0
        playMoveFirst = false
        play.isMoving = false
        play.moveAnimTime = 0
    end
    prevPlayLeft = curLeft
    prevPlayRight = curRight

    -- 跳跃
    if input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP) then
        if play.isOnGround and not play.isJumping then
            play.isJumping = true
            play.jumpGridsRemain = PlayCalcJump()
            play.isOnGround = false
            play.jumpTimer = 0
        end
    end

    -- 垂直物理
    if play.isJumping and play.jumpGridsRemain > 0 then
        play.jumpTimer = play.jumpTimer + dt
        if play.jumpTimer >= PLAY_JUMP_TICK then
            play.jumpTimer = 0
            local newY = play.gridY - 1
            if not PlayCollides(play.gridX, newY) then
                play.gridY = newY
                play.jumpGridsRemain = play.jumpGridsRemain - 1
            else
                play.jumpGridsRemain = 0
            end
        end
        if play.jumpGridsRemain <= 0 then
            play.isJumping = false
            play.fallTickCurrent = PLAY_FALL_BASE
        end
    else
        if not PlayOnGround(play.gridX, play.gridY) then
            play.isOnGround = false
            play.fallTimer = play.fallTimer + dt
            play.fallAnimTime = play.fallAnimTime + dt
            if play.fallTimer >= play.fallTickCurrent then
                play.fallTimer = 0
                local newY = play.gridY + 1
                if newY > MAP_ROWS then
                    if editorMode == MODE_WORLDPLAY then
                        play.gridY = MAP_ROWS  -- 触发边界检测
                        return
                    end
                    play.alive = false
                    return
                end
                if not PlayCollides(play.gridX, newY) then
                    play.gridY = newY
                    play.fallTickCurrent = math.max(PLAY_FALL_MIN, play.fallTickCurrent - PLAY_FALL_ACCEL)
                    -- 每下降1格：剥离 totalPixels/10 像素
                    play.fallGridCount = play.fallGridCount + 1
                    -- 超过最大下落格数则死亡
                    if play.fallGridCount >= playerParams.maxFallGrids then
                        play.alive = false
                        return
                    end
                    local stripCount = math.max(1, math.floor(playTotalPixels / 10 + 0.5))
                    PlayStripPixels(stripCount)
                else
                    play.isOnGround = true
                    play.fallTickCurrent = PLAY_FALL_BASE
                    play.fallAnimTime = 0
                end
            end
        else
            play.isOnGround = true
            play.isJumping = false
            play.fallTickCurrent = PLAY_FALL_BASE
            play.fallAnimTime = 0
        end
    end

    -- 落地缓慢恢复
    if play.isOnGround and playAlivePixels < playTotalPixels then
        local recoverCount = math.floor(PLAY_RECOVER_PER_SEC * dt + 0.5)
        if recoverCount >= 1 then
            PlayRecoverPixels(recoverCount)
            local pixelsPerGrid = math.max(1, math.floor(playTotalPixels / 10 + 0.5))
            local expectedFallCount = math.floor((playTotalPixels - playAlivePixels) / pixelsPerGrid)
            play.fallGridCount = math.max(0, expectedFallCount)
        end
    end

    if playAlivePixels <= 0 then
        play.alive = false
    end

    -- 碰撞检测道具/陷阱
    PlayCheckTiles()

    -- 相机跟随（受摄像机边界限制）
    local boundLeftPx = (camBound.left - 1) * GRID
    local boundRightPx = camBound.right * GRID
    local viewW = DESIGN_W
    -- 相机 X 范围：限制在边界内
    local camMinX = boundLeftPx
    local camMaxX = math.max(boundLeftPx, boundRightPx - viewW)

    local targetCam = (play.gridX - 1) * GRID - viewW * 0.35
    targetCam = math.max(camMinX, math.min(targetCam, camMaxX))
    playCameraX = playCameraX + (targetCam - playCameraX) * math.min(1, dt * 8)
end

-- ====================================================================
-- 试玩模式渲染（完整火焰效果）
-- ====================================================================

--- 绘制火焰玩家（逐像素渲染，带动画偏移和闪烁）
local function DrawPlayFlame()
    local baseX = (play.gridX - 1) * GRID - playCameraX
    local baseY = (play.gridY - 1) * GRID
    local ps = FLAME_CFG.pixelSize
    local N = FLAME_CFG.pixelGridSize
    local totalSize = N * ps

    -- 火焰中心
    local pivotX = baseX + totalSize * 0.5
    local pivotY = baseY + totalSize

    -- 光晕
    local glowRadius = totalSize * 0.6 * (playAlivePixels / math.max(1, playTotalPixels))
    local glowAlpha = math.floor(40 + 20 * math.sin(playGameTime * FLAME_CFG.flickerSpeed))
    nvgBeginPath(vg)
    nvgCircle(vg, pivotX, pivotY - totalSize * 0.5, glowRadius)
    nvgFillColor(vg, nvgRGBA(255, 120, 0, glowAlpha))
    nvgFill(vg)

    -- 逐像素绘制：预计算合并偏移（含宽度限制+三遍平滑）
    local brightFrame = flameAnimFrame
    local combinedH = {}
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
        local raw = rowOffsets[row] or 0
        local w = rowWidth[row]
        local maxShift
        if w <= 2 then
            maxShift = 0
        elseif w <= 4 then
            maxShift = 1
        else
            maxShift = math.max(1, math.floor(w * 0.3))
        end
        combinedH[row] = math.max(-maxShift, math.min(maxShift, raw))
    end
    combinedH[N] = 0
    combinedH[N - 1] = 0
    for row = N - 2, 1, -1 do
        local diff = combinedH[row] - combinedH[row + 1]
        if diff > 1 then combinedH[row] = combinedH[row + 1] + 1
        elseif diff < -1 then combinedH[row] = combinedH[row + 1] - 1 end
    end
    for row = 2, N do
        local diff = combinedH[row] - combinedH[row - 1]
        if diff > 1 then combinedH[row] = combinedH[row - 1] + 1
        elseif diff < -1 then combinedH[row] = combinedH[row - 1] - 1 end
    end
    for row = N - 2, 1, -1 do
        local diff = combinedH[row] - combinedH[row + 1]
        if diff > 1 then combinedH[row] = combinedH[row + 1] + 1
        elseif diff < -1 then combinedH[row] = combinedH[row + 1] - 1 end
    end

    for row = 1, N do
        local hShift = combinedH[row]

        for col = 1, N do
            if pixelState[row][col] then
                local baseColor = FLAME_COLORS[row]

                -- 亮度闪烁（离散跳变）
                local flickSeed = (brightFrame * 3 + row * 7 + col * 13) % 10
                local brightness
                if flickSeed < 2 then
                    brightness = 1.25
                elseif flickSeed < 5 then
                    brightness = 1.0
                else
                    brightness = 0.85
                end
                if row <= 2 then brightness = brightness + 0.15 end
                local cx = (N + 1) / 2
                if math.abs(col - cx) >= 3 then brightness = brightness * 0.85 end

                local r = math.min(255, math.max(0, math.floor(baseColor[1] * brightness)))
                local g = math.min(255, math.max(0, math.floor(baseColor[2] * brightness)))
                local b = math.min(255, math.max(0, math.floor(baseColor[3] * brightness)))

                local drawCol = col
                if not play.facingRight then drawCol = N - col + 1 end

                local px = baseX + (drawCol - 1 + hShift) * ps
                local py = baseY + (row - 1) * ps

                nvgBeginPath(vg)
                nvgRect(vg, px, py, ps, ps)
                nvgFillColor(vg, nvgRGBA(r, g, b, 255))
                nvgFill(vg)
            end
        end
    end

    -- 下落火星粒子绘制
    for _, p in ipairs(playFallParticles) do
        local screenX = p.x - playCameraX
        local screenY = p.y
        local progress = 1.0 - p.life / p.maxLife
        local alpha = math.floor((1.0 - progress) * 255)
        if alpha > 10 then
            local baseColor = FLAME_COLORS[p.colorRow] or FLAME_COLORS[7]
            local r = math.min(255, math.floor(baseColor[1] * (1.0 + (1.0 - progress) * 0.2)))
            local g = math.floor(baseColor[2] * (1.0 - progress * 0.3))
            local b = math.floor(baseColor[3] * (1.0 - progress * 0.5))
            local sz = p.size * (1.0 - progress * 0.5)
            nvgBeginPath(vg)
            nvgRect(vg, screenX, screenY, sz, sz)
            nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
            nvgFill(vg)
        end
    end
end

local function DrawPlayMode()
    -- 渐变夜空背景
    local bg = nvgLinearGradient(vg, 0, 0, 0, screenDesignH,
        nvgRGBA(10, 5, 20, 255), nvgRGBA(30, 15, 40, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenDesignW, screenDesignH)
    nvgFillPaint(vg, bg)
    nvgFill(vg)

    -- 网格
    local startCol = math.max(1, math.floor(playCameraX / GRID) + 1)
    local endCol = math.min(MAP_COLS, startCol + math.ceil(screenDesignW / GRID) + 2)

    -- 细线
    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        local x = (col - 1) * GRID - playCameraX
        nvgMoveTo(vg, x, 0)
        nvgLineTo(vg, x, MAP_ROWS * GRID)
    end
    for row = 1, MAP_ROWS + 1 do
        local y = (row - 1) * GRID
        nvgMoveTo(vg, (startCol - 1) * GRID - playCameraX, y)
        nvgLineTo(vg, endCol * GRID - playCameraX, y)
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 15))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- 每5格加粗
    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        if (col - 1) % 5 == 0 then
            local x = (col - 1) * GRID - playCameraX
            nvgMoveTo(vg, x, 0)
            nvgLineTo(vg, x, MAP_ROWS * GRID)
        end
    end
    for row = 1, MAP_ROWS + 1 do
        if (row - 1) % 5 == 0 then
            local y = (row - 1) * GRID
            nvgMoveTo(vg, (startCol - 1) * GRID - playCameraX, y)
            nvgLineTo(vg, endCol * GRID - playCameraX, y)
        end
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 35))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 地块渲染
    for row = 1, MAP_ROWS do
        for col = startCol, endCol do
            local val = levelData[row][col]
            if val == TILE.EMPTY or val == TILE.SPAWN then goto continueTile end
            local px = (col - 1) * GRID - playCameraX
            local py = (row - 1) * GRID
            local base, group = GetTileType(val)

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

            elseif base == TILE.FUEL then
                local key = row .. "_" .. col
                if not play.collected[key] then
                    -- 闪烁火种
                    local flicker = math.sin(playGameTime * 6 + col * 1.7) * 0.3 + 0.7
                    local fr = math.floor(255 * flicker)
                    local fg = math.floor(120 * flicker)
                    nvgBeginPath(vg)
                    nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 7)
                    nvgFillColor(vg, nvgRGBA(255, 100, 0, math.floor(60 * flicker)))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 4)
                    nvgFillColor(vg, nvgRGBA(fr, fg, 10, 255))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5 - 1, 2)
                    nvgFillColor(vg, nvgRGBA(255, 255, 200, math.floor(200 * flicker)))
                    nvgFill(vg)
                end

            elseif base == TILE.GOAL then
                -- 旗帜终点
                nvgBeginPath(vg)
                nvgRect(vg, px + 7, py, 2, GRID)
                nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgMoveTo(vg, px + 9, py + 2)
                nvgLineTo(vg, px + 9 + 6, py + 5)
                nvgLineTo(vg, px + 9, py + 8)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(100, 255, 100, 255))
                nvgFill(vg)

            elseif base == TILE.SPIKE then
                -- 尖刺（带闪光）
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
                local key = row .. "_" .. col
                local gc = GROUP_COLORS[group] or GROUP_COLORS[1]
                local activated = play.collected[key]
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
                local gc = GROUP_COLORS[group] or GROUP_COLORS[1]
                local open = play.switchState[group]
                if not open then
                    -- 闭合门（栏杆效果）
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 1, py, GRID - 2, GRID)
                    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 180))
                    nvgFill(vg)
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
                if not play.hiddenWallRevealed[group] then
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

    -- 绘制火焰主角
    DrawPlayFlame()

    -- 战争迷雾（试玩模式强制开启）
    FogOfWar.SetLightSources(FogOfWar.GetLightSources())
    FogOfWar.Draw(vg, {
        gridSize = GRID,
        startCol = startCol,
        endCol = endCol,
        startRow = 1,
        endRow = MAP_ROWS,
        offsetX = playCameraX,
        offsetY = 0,
        zoomLevel = 1.0,
        mapX = 0,
        mapY = 0,
    })

    -- HUD
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenDesignW, 22)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    local flamePercent = math.floor(playAlivePixels / math.max(1, playTotalPixels) * 100)
    local flameG = math.floor(200 * (flamePercent / 100))
    nvgFillColor(vg, nvgRGBA(255, flameG, 30, 255))
    nvgText(vg, 6, 11, "FLAME:" .. flamePercent .. "%")

    nvgFillColor(vg, nvgRGBA(150, 255, 150, 255))
    nvgText(vg, 100, 11, "JUMP:" .. PlayCalcJump() .. "G")

    -- 返回按钮（可点击）
    local isWorldPlay = (editorMode == MODE_WORLDPLAY)
    local backBtnLabel = isWorldPlay and "返回世界" or "返回编辑"
    local backBtnW = isWorldPlay and 60 or 50
    local backBtnH = 16
    local backBtnX = screenDesignW - backBtnW - 6
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

    -- 世界试玩模式：显示当前关卡名
    if isWorldPlay and worldPlayCurrentFile then
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, 200))
        nvgText(vg, screenDesignW * 0.5, 3, worldPlayCurrentFile)
    end

    -- 死亡/通关覆盖
    local escHint = isWorldPlay and "ESC:返回世界地图" or "ESC:返回编辑"
    if not play.alive then
        -- 半透明遮罩
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, screenDesignW, screenDesignH)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
        nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(255, 60, 60, 255))
        nvgText(vg, screenDesignW * 0.5, screenDesignH * 0.4, "FLAME OUT!")
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, screenDesignW * 0.5, screenDesignH * 0.52, "R:重试  " .. escHint)
    elseif play.won then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, screenDesignW, screenDesignH)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
        nvgFill(vg)

        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
        nvgText(vg, screenDesignW * 0.5, screenDesignH * 0.4, "FLAME ETERNAL!")
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, screenDesignW * 0.5, screenDesignH * 0.52, escHint)
    end
end

-- ====================================================================
-- 编辑模式渲染
-- ====================================================================
local function DrawToolbar()
    -- 底部工具栏区域（位于状态栏上方）
    local barY = screenDesignH - BOTTOMBAR_H
    local toolBarH = BOTTOMBAR_H - 16  -- 上部为工具按钮区，下部16px为状态栏

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, barY, screenDesignW, toolBarH)
    nvgFillColor(vg, nvgRGBA(25, 25, 35, 245))
    nvgFill(vg)

    -- 顶部分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, barY)
    nvgLineTo(vg, screenDesignW, barY)
    nvgStrokeColor(vg, nvgRGBA(80, 80, 100, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- === 交互模式切换按钮（左下角竖向排列，不遮挡工具按钮） ===
    local modeBtnW = 20
    local modeBtnH = 11
    local modeBtnPad = 2
    local modeBtnStartX = 6
    local modeBtnStartY = barY + 3

    local INTERACT_MODES = {
        { id = INTERACT_DRAW,   icon = "✎", label = "绘制", key = "R" },
        { id = INTERACT_SELECT, icon = "⊙", label = "选取", key = "Q" },
        { id = INTERACT_MOVE,   icon = "✥", label = "移动", key = "E" },
    }

    for i, mode in ipairs(INTERACT_MODES) do
        local mbx = modeBtnStartX
        local mby = modeBtnStartY + (i - 1) * (modeBtnH + modeBtnPad)
        local isActive = (interactMode == mode.id)

        -- 按钮背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, mbx, mby, modeBtnW, modeBtnH, 3)
        if isActive then
            nvgFillColor(vg, nvgRGBA(60, 130, 220, 255))
        else
            nvgFillColor(vg, nvgRGBA(40, 42, 55, 255))
        end
        nvgFill(vg)

        -- 选中边框
        if isActive then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, mbx - 1, mby - 1, modeBtnW + 2, modeBtnH + 2, 4)
            nvgStrokeColor(vg, nvgRGBA(100, 180, 255, 220))
            nvgStrokeWidth(vg, 1.0)
            nvgStroke(vg)
        end

        -- 快捷键 + 图标
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 8)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, isActive and 255 or 160))
        nvgText(vg, mbx + modeBtnW * 0.5, mby + modeBtnH * 0.5, mode.key)
    end

    -- 水平排列工具按钮（居中，不受模式按钮影响）
    local btnW = 36
    local btnH = 28
    local btnPad = 4
    local totalW = #TOOLS * (btnW + btnPad) - btnPad
    local startX = (screenDesignW - totalW) * 0.5  -- 居中
    local btnY = barY + (toolBarH - btnH) * 0.5

    for i, tool in ipairs(TOOLS) do
        local bx = startX + (i - 1) * (btnW + btnPad)

        -- 分组颜色色带（按钮底部3px色条）
        local gc = GetToolGroupColor(tool)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, btnY + btnH - 3, btnW, 3, 1)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], i == currentTool and 255 or 120))
        nvgFill(vg)

        -- 选中高亮边框
        if i == currentTool then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx - 2, btnY - 2, btnW + 4, btnH + 4, 5)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end

        -- 按钮背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, btnY, btnW, btnH - 3, 3)
        local c = tool.color
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], i == currentTool and 255 or 120))
        nvgFill(vg)

        -- 工具名称
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
        nvgText(vg, bx + btnW * 0.5, btnY + (btnH - 3) * 0.5 - 2, tool.name)

        -- 快捷键编号
        nvgFontSize(vg, 7)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 150))
        nvgText(vg, bx + btnW * 0.5, btnY + (btnH - 3) * 0.5 + 7, tostring(i))
    end

    -- 颜色分组指示器（始终显示在工具栏右侧，当前选色一目了然）
    local indicatorX = startX + totalW + 12
    local indicatorY = btnY + btnH * 0.5
    local sgc = GROUP_COLORS[currentGroup]

    -- 绘制所有4个颜色选项，当前选中的高亮放大
    for gi = 1, MAX_GROUPS do
        local gc = GROUP_COLORS[gi]
        local gx = indicatorX + (gi - 1) * 14
        local radius = (gi == currentGroup) and 6 or 4
        local alpha = (gi == currentGroup) and 255 or 100
        nvgBeginPath(vg)
        nvgCircle(vg, gx, indicatorY - 2, radius)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], alpha))
        nvgFill(vg)
        -- 选中的加白色边框
        if gi == currentGroup then
            nvgBeginPath(vg)
            nvgCircle(vg, gx, indicatorY - 2, radius + 1.5)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end

    -- 分组文字标签
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(sgc[1], sgc[2], sgc[3], 255))
    nvgText(vg, indicatorX + MAX_GROUPS * 14 + 2, indicatorY - 2, GROUP_NAMES[currentGroup] .. " [G]")
end

-- 顶栏按钮定义（按功能分组排列）
local topBarButtons = {}

-- 按钮形状类型
BTN_SHAPE_CIRCLE, BTN_SHAPE_PILL, BTN_SHAPE_ROUNDED = "circle", "pill", "rounded"
BTN_GROUP_PLAY, BTN_GROUP_FILE, BTN_GROUP_CONFIG, BTN_GROUP_MODE = "play", "file", "config", "mode"

function InitTopBarButtons()
    -- 按钮位置将在渲染时按设计坐标计算
    -- shape: 按钮形状    group: 功能分组    hasSubmenu: 是否有二级菜单（显示▾三角）
    topBarButtons = {
        -- 左上角：试玩（圆形开关，最醒目）
        { id = "play",     label = "▶",   x = 0, y = 0, w = 18, h = 18, shape = BTN_SHAPE_CIRCLE,  group = BTN_GROUP_PLAY },
        -- 文件操作组
        { id = "save",     label = "保存", x = 0, y = 0, w = 34, h = 14, shape = BTN_SHAPE_ROUNDED, group = BTN_GROUP_FILE },
        { id = "saveNew",  label = "另存", x = 0, y = 0, w = 34, h = 14, shape = BTN_SHAPE_ROUNDED, group = BTN_GROUP_FILE },
        -- 配置组（带二级菜单标识）
        { id = "canvas",   label = "画布", x = 0, y = 0, w = 38, h = 14, shape = BTN_SHAPE_PILL, group = BTN_GROUP_CONFIG, hasSubmenu = true },
        { id = "player",   label = "玩家", x = 0, y = 0, w = 38, h = 14, shape = BTN_SHAPE_PILL, group = BTN_GROUP_CONFIG, hasSubmenu = true },
        { id = "fog",      label = "迷雾", x = 0, y = 0, w = 34, h = 14, shape = BTN_SHAPE_PILL, group = BTN_GROUP_CONFIG },
        -- 模式切换组
        { id = "random",   label = "随机", x = 0, y = 0, w = 34, h = 14, shape = BTN_SHAPE_ROUNDED, group = BTN_GROUP_MODE },
        { id = "worldmap", label = "世界", x = 0, y = 0, w = 34, h = 14, shape = BTN_SHAPE_ROUNDED, group = BTN_GROUP_MODE, hasSubmenu = true },
        { id = "sidebar",  label = "关卡", x = 0, y = 0, w = 34, h = 14, shape = BTN_SHAPE_ROUNDED, group = BTN_GROUP_MODE },
    }
end

-- 绘制小三角标识（表示有二级菜单/弹窗）
local function DrawSubmenuTriangle(cx, cy, size)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - size * 0.5, cy - size * 0.3)
    nvgLineTo(vg, cx + size * 0.5, cy - size * 0.3)
    nvgLineTo(vg, cx, cy + size * 0.5)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 180))
    nvgFill(vg)
end

function DrawTopBar()
    -- 顶栏背景（微渐变效果）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenDesignW, TOPBAR_H)
    nvgFillPaint(vg, nvgLinearGradient(vg, 0, 0, 0, TOPBAR_H, nvgRGBA(28, 28, 40, 250), nvgRGBA(18, 18, 28, 250)))
    nvgFill(vg)

    -- 底部高光线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, TOPBAR_H - 0.5)
    nvgLineTo(vg, screenDesignW, TOPBAR_H - 0.5)
    nvgStrokeColor(vg, nvgRGBA(60, 65, 80, 200))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")

    -- === 按功能分组从左到右排列 ===
    local curX = 4  -- 起始x坐标
    local centerY = TOPBAR_H * 0.5
    local groupGap = 10   -- 分组间距
    local btnGap = 3      -- 组内按钮间距
    local lastGroup = nil

    for _, btn in ipairs(topBarButtons) do
        -- 分组间增加间距 + 分隔线
        if lastGroup and btn.group ~= lastGroup then
            curX = curX + groupGap
            -- 绘制分组分隔符（小圆点）
            nvgBeginPath(vg)
            nvgCircle(vg, curX - groupGap * 0.5, centerY, 1.2)
            nvgFillColor(vg, nvgRGBA(80, 85, 100, 150))
            nvgFill(vg)
        end
        lastGroup = btn.group

        -- 获取按钮颜色
        local bgR, bgG, bgB, bgA = 45, 50, 65, 255
        local borderR, borderG, borderB, borderA = 80, 85, 100, 150
        local textR, textG, textB = 230, 230, 240
        local isActive = false

        if btn.id == "play" then
            bgR, bgG, bgB = 30, 160, 90   -- 绿色播放按钮
            borderR, borderG, borderB, borderA = 50, 200, 120, 200
            textR, textG, textB = 255, 255, 255
        elseif btn.id == "save" then
            bgR, bgG, bgB = 45, 100, 65
            borderR, borderG, borderB = 70, 140, 90
        elseif btn.id == "saveNew" then
            bgR, bgG, bgB = 50, 80, 70
            borderR, borderG, borderB = 70, 120, 90
        elseif btn.id == "canvas" then
            bgR, bgG, bgB = 60, 75, 90
            borderR, borderG, borderB = 90, 110, 140
        elseif btn.id == "player" then
            bgR, bgG, bgB = 75, 65, 50
            borderR, borderG, borderB = 130, 110, 70
        elseif btn.id == "fog" then
            isActive = fogShowInEditor
            if isActive then
                bgR, bgG, bgB = 50, 55, 110
                borderR, borderG, borderB, borderA = 90, 100, 200, 220
                textR, textG, textB = 160, 180, 255
            else
                bgR, bgG, bgB = 35, 38, 55
                borderR, borderG, borderB = 60, 65, 80
                textR, textG, textB = 140, 140, 160
            end
        elseif btn.id == "random" then
            bgR, bgG, bgB = 100, 60, 35
            borderR, borderG, borderB = 160, 100, 50
        elseif btn.id == "worldmap" then
            isActive = (editorMode == MODE_WORLDMAP)
            if isActive then
                bgR, bgG, bgB = 90, 45, 110
                borderR, borderG, borderB, borderA = 150, 80, 200, 220
            else
                bgR, bgG, bgB = 55, 40, 70
                borderR, borderG, borderB = 90, 65, 120
            end
        elseif btn.id == "sidebar" then
            isActive = sidebarOpen
            if isActive then
                bgR, bgG, bgB = 70, 60, 45
                borderR, borderG, borderB, borderA = 130, 110, 70, 200
            else
                bgR, bgG, bgB = 45, 42, 38
                borderR, borderG, borderB = 80, 70, 60
            end
        end

        -- 根据形状绘制按钮
        if btn.shape == BTN_SHAPE_CIRCLE then
            -- === 圆形按钮（试玩开关）===
            local radius = btn.w * 0.5
            local cx = curX + radius
            local cy = centerY
            btn.x = curX
            btn.y = cy - radius
            btn.w = radius * 2
            btn.h = radius * 2

            -- 外发光（激活时更亮）
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, radius + 2)
            nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, 60))
            nvgFill(vg)

            -- 按钮主体
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, radius)
            local circlePaint = nvgRadialGradient(vg, cx, cy - 2, 1, radius, nvgRGBA(bgR + 30, bgG + 30, bgB + 30, 255), nvgRGBA(bgR, bgG, bgB, 255))
            nvgFillPaint(vg, circlePaint)
            nvgFill(vg)

            -- 边框
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, radius)
            nvgStrokeColor(vg, nvgRGBA(borderR, borderG, borderB, borderA))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            -- 图标（播放三角）
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(textR, textG, textB, 255))
            nvgText(vg, cx + 1, cy, btn.label)

            curX = curX + btn.w + btnGap

        elseif btn.shape == BTN_SHAPE_PILL then
            -- === 椭圆药丸形（配置类按钮）===
            local bw = btn.w
            local bh = btn.h
            local bx = curX
            local by = centerY - bh * 0.5
            btn.x = bx
            btn.y = by

            -- 药丸形背景（圆角 = 高度一半）
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, bw, bh, bh * 0.5)
            nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, bgA))
            nvgFill(vg)

            -- 边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, bw, bh, bh * 0.5)
            nvgStrokeColor(vg, nvgRGBA(borderR, borderG, borderB, borderA))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)

            -- 文字（如果有二级菜单，文字左移为三角腾出空间）
            local textOffsetX = btn.hasSubmenu and -3 or 0
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(textR, textG, textB, 255))
            nvgText(vg, bx + bw * 0.5 + textOffsetX, by + bh * 0.5, btn.label)

            -- 二级菜单三角标识
            if btn.hasSubmenu then
                DrawSubmenuTriangle(bx + bw - 8, by + bh * 0.5, 5)
            end

            curX = curX + bw + btnGap

        else
            -- === 圆角矩形（默认）===
            local bw = btn.w
            local bh = btn.h
            local bx = curX
            local by = centerY - bh * 0.5
            btn.x = bx
            btn.y = by

            -- 按钮背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, bw, bh, 4)
            nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, bgA))
            nvgFill(vg)

            -- 边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, bw, bh, 4)
            nvgStrokeColor(vg, nvgRGBA(borderR, borderG, borderB, borderA))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)

            -- 激活状态的顶部高亮条
            if isActive then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx + 2, by, bw - 4, 2, 1)
                nvgFillColor(vg, nvgRGBA(borderR, borderG, borderB, 200))
                nvgFill(vg)
            end

            -- 文字
            local textOffsetX = btn.hasSubmenu and -3 or 0
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(textR, textG, textB, 255))
            nvgText(vg, bx + bw * 0.5 + textOffsetX, by + bh * 0.5, btn.label)

            -- 二级菜单三角标识
            if btn.hasSubmenu then
                DrawSubmenuTriangle(bx + bw - 7, by + bh * 0.5, 4.5)
            end

            curX = curX + bw + btnGap
        end
    end

    -- 右侧显示当前模式/工具信息
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 165, 180, 200))
    if editorMode == MODE_WORLDMAP then
        nvgText(vg, screenDesignW - 6, centerY, "世界地图模式")
    else
        nvgFillColor(vg, nvgRGBA(200, 200, 210, 200))
        nvgText(vg, screenDesignW - 6, centerY, "工具:" .. TOOLS[currentTool].name)
    end
end

function DrawBottomBar()
    -- 底部状态栏（16px高，位于工具栏下方）
    local statusH = 16
    local by = screenDesignH - statusH
    nvgBeginPath(vg)
    nvgRect(vg, 0, by, screenDesignW, statusH)
    nvgFillColor(vg, nvgRGBA(15, 15, 25, 250))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 200))
    local diffName = DIFFICULTY_NAMES[DIFFICULTIES[currentDifficulty]] or "普通"
    nvgText(vg, 6, by + statusH * 0.5, "左键:放置  右键:擦除  AD:滚动  1-7:工具  R:随机  T:难度[" .. diffName .. "]")

    if msgTimer > 0 then
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 255, 100, math.min(255, math.floor(msgTimer * 255))))
        nvgText(vg, screenDesignW - 6, by + statusH * 0.5, msgText)
    end
end

function DrawSidebar()
    if not sidebarOpen then return end

    local sbX = screenDesignW - SIDEBAR_W
    local sbY = TOPBAR_H
    local sbH = screenDesignH - TOPBAR_H - BOTTOMBAR_H

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, sbX, sbY, SIDEBAR_W, sbH)
    nvgFillColor(vg, nvgRGBA(22, 22, 35, 245))
    nvgFill(vg)

    -- 左边框线
    nvgBeginPath(vg)
    nvgMoveTo(vg, sbX, sbY)
    nvgLineTo(vg, sbX, sbY + sbH)
    nvgStrokeColor(vg, nvgRGBA(80, 80, 100, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 200, 80, 255))
    nvgText(vg, sbX + SIDEBAR_W * 0.5, sbY + 10, "已保存关卡")

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, sbX + 6, sbY + 20)
    nvgLineTo(vg, sbX + SIDEBAR_W - 6, sbY + 20)
    nvgStrokeColor(vg, nvgRGBA(60, 60, 80, 255))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- 关卡列表
    nvgSave(vg)
    nvgScissor(vg, sbX, sbY + 22, SIDEBAR_W, sbH - 22)

    local itemH = 22
    local listY = sbY + 24 - sidebarScroll

    if #savedLevels == 0 then
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(120, 120, 140, 200))
        nvgText(vg, sbX + SIDEBAR_W * 0.5, sbY + sbH * 0.5, "暂无保存")
    else
        local actionBtnSize = 14
        local actionPad = 2

        for i, lv in ipairs(savedLevels) do
            local iy = listY + (i - 1) * itemH
            if iy + itemH < sbY + 22 or iy > sbY + sbH then goto continueSidebar end

            -- 高亮当前编辑的关卡
            local isCurrent = (lv.file == currentLevelName)

            -- 悬停检测
            local mx = input:GetMousePosition().x / dpr / scaleF
            local my = input:GetMousePosition().y / dpr / scaleF
            local isHover = mx >= sbX and mx < sbX + SIDEBAR_W and my >= iy and my < iy + itemH

            -- 背景
            if isCurrent then
                nvgBeginPath(vg)
                nvgRect(vg, sbX + 4, iy + 1, SIDEBAR_W - 8, itemH - 2)
                nvgFillColor(vg, nvgRGBA(60, 80, 40, 200))
                nvgFill(vg)
            elseif isHover then
                nvgBeginPath(vg)
                nvgRect(vg, sbX + 4, iy + 1, SIDEBAR_W - 8, itemH - 2)
                nvgFillColor(vg, nvgRGBA(50, 50, 70, 200))
                nvgFill(vg)
            end

            -- 关卡名（留出右侧按钮空间）
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            if isCurrent then
                nvgFillColor(vg, nvgRGBA(150, 255, 150, 255))
            else
                nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
            end
            nvgText(vg, sbX + 10, iy + itemH * 0.5, lv.name)

            -- 操作按钮（仅在悬停时显示）
            if isHover then
                local btnY2 = iy + (itemH - actionBtnSize) * 0.5
                -- 删除按钮 (最右)
                local delX = sbX + SIDEBAR_W - 8 - actionBtnSize
                local isDelHover = mx >= delX and mx < delX + actionBtnSize and my >= btnY2 and my < btnY2 + actionBtnSize
                nvgBeginPath(vg)
                nvgRoundedRect(vg, delX, btnY2, actionBtnSize, actionBtnSize, 2)
                nvgFillColor(vg, isDelHover and nvgRGBA(180, 50, 50, 220) or nvgRGBA(100, 40, 40, 180))
                nvgFill(vg)
                -- X 图标
                nvgBeginPath(vg)
                nvgMoveTo(vg, delX + 4, btnY2 + 4)
                nvgLineTo(vg, delX + actionBtnSize - 4, btnY2 + actionBtnSize - 4)
                nvgMoveTo(vg, delX + actionBtnSize - 4, btnY2 + 4)
                nvgLineTo(vg, delX + 4, btnY2 + actionBtnSize - 4)
                nvgStrokeColor(vg, nvgRGBA(255, 200, 200, 255))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)

                -- 重命名按钮 (删除按钮左边)
                local renX = delX - actionBtnSize - actionPad
                local isRenHover = mx >= renX and mx < renX + actionBtnSize and my >= btnY2 and my < btnY2 + actionBtnSize
                nvgBeginPath(vg)
                nvgRoundedRect(vg, renX, btnY2, actionBtnSize, actionBtnSize, 2)
                nvgFillColor(vg, isRenHover and nvgRGBA(60, 100, 160, 220) or nvgRGBA(40, 70, 120, 180))
                nvgFill(vg)
                -- 铅笔图标 (简化为斜线+底横)
                nvgBeginPath(vg)
                nvgMoveTo(vg, renX + 4, btnY2 + actionBtnSize - 5)
                nvgLineTo(vg, renX + actionBtnSize - 4, btnY2 + 4)
                nvgStrokeColor(vg, nvgRGBA(180, 210, 255, 255))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
                nvgBeginPath(vg)
                nvgMoveTo(vg, renX + 3, btnY2 + actionBtnSize - 4)
                nvgLineTo(vg, renX + 7, btnY2 + actionBtnSize - 4)
                nvgStrokeColor(vg, nvgRGBA(180, 210, 255, 255))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end

            ::continueSidebar::
        end
    end

    nvgRestore(vg)
end

-- ====================================================================
-- 对话框绘制
-- ====================================================================
function DrawDialog()
    if not dialogMode then return end

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenDesignW, screenDesignH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    local dlgW = 180
    local dlgH = 65
    if dialogMode == "rename" then dlgH = 80
    elseif dialogMode == "canvas" then dlgH = 100
    elseif dialogMode == "player" then dlgW = 200; dlgH = 150
    elseif dialogMode == "light" then dlgH = 100 end
    local dlgX = (screenDesignW - dlgW) * 0.5
    local dlgY = (screenDesignH - dlgH) * 0.5

    -- 对话框背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, 6)
    nvgFillColor(vg, nvgRGBA(30, 30, 45, 250))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, 6)
    nvgStrokeColor(vg, nvgRGBA(100, 110, 140, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")

    if dialogMode == "rename" then
        -- 标题
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
        nvgText(vg, dlgX + dlgW * 0.5, dlgY + 14, "重命名关卡")

        -- 输入框
        local inputX = dlgX + 12
        local inputY = dlgY + 26
        local inputW = dlgW - 24
        local inputH = 18
        nvgBeginPath(vg)
        nvgRoundedRect(vg, inputX, inputY, inputW, inputH, 3)
        nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, inputX, inputY, inputW, inputH, 3)
        nvgStrokeColor(vg, nvgRGBA(80, 120, 200, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 输入文本
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
        nvgText(vg, inputX + 4, inputY + inputH * 0.5, renameInput)

        -- 闪烁光标
        if math.floor(renameBlink * 2) % 2 == 0 then
            local cursorText = string.sub(renameInput, 1, renameCursor)
            local bounds = {}
            local tw = nvgTextBounds(vg, 0, 0, cursorText, bounds)
            local cursorX = inputX + 4 + tw
            nvgBeginPath(vg)
            nvgMoveTo(vg, cursorX, inputY + 3)
            nvgLineTo(vg, cursorX, inputY + inputH - 3)
            nvgStrokeColor(vg, nvgRGBA(200, 220, 255, 255))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- 按钮
        local btnW2 = 50
        local btnH2 = 16
        local btnY3 = dlgY + dlgH - btnH2 - 10
        local confirmX = dlgX + dlgW * 0.5 - btnW2 - 6
        local cancelX = dlgX + dlgW * 0.5 + 6

        -- 确认按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, confirmX, btnY3, btnW2, btnH2, 3)
        nvgFillColor(vg, nvgRGBA(40, 120, 60, 255))
        nvgFill(vg)
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 255, 240, 255))
        nvgText(vg, confirmX + btnW2 * 0.5, btnY3 + btnH2 * 0.5, "确认")

        -- 取消按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cancelX, btnY3, btnW2, btnH2, 3)
        nvgFillColor(vg, nvgRGBA(80, 70, 70, 255))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
        nvgText(vg, cancelX + btnW2 * 0.5, btnY3 + btnH2 * 0.5, "取消")

    elseif dialogMode == "delete" then
        -- 标题
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 100, 80, 255))
        nvgText(vg, dlgX + dlgW * 0.5, dlgY + 14, "删除关卡")

        -- 提示文本
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
        local targetName = dialogTarget and dialogTarget.name or ""
        nvgText(vg, dlgX + dlgW * 0.5, dlgY + 30, "确定删除 \"" .. targetName .. "\" ?")

        -- 按钮
        local btnW2 = 50
        local btnH2 = 16
        local btnY3 = dlgY + dlgH - btnH2 - 10
        local confirmX = dlgX + dlgW * 0.5 - btnW2 - 6
        local cancelX = dlgX + dlgW * 0.5 + 6

        -- 删除按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, confirmX, btnY3, btnW2, btnH2, 3)
        nvgFillColor(vg, nvgRGBA(160, 40, 40, 255))
        nvgFill(vg)
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 220, 255))
        nvgText(vg, confirmX + btnW2 * 0.5, btnY3 + btnH2 * 0.5, "删除")

        -- 取消按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cancelX, btnY3, btnW2, btnH2, 3)
        nvgFillColor(vg, nvgRGBA(80, 70, 70, 255))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
        nvgText(vg, cancelX + btnW2 * 0.5, btnY3 + btnH2 * 0.5, "取消")

    elseif dialogMode == "canvas" then
        -- 标题
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 220, 100, 255))
        nvgText(vg, dlgX + dlgW * 0.5, dlgY + 14, "画布大小")

        -- 当前大小提示
        nvgFontSize(vg, 8)
        nvgFillColor(vg, nvgRGBA(140, 140, 160, 200))
        nvgText(vg, dlgX + dlgW * 0.5, dlgY + 26, "范围: 宽10~200  高5~100")

        -- 宽度标签+输入框
        local inputW = 50
        local inputH = 16
        local fieldY1 = dlgY + 34
        local fieldY2 = dlgY + 56

        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
        nvgText(vg, dlgX + dlgW * 0.5 - inputW * 0.5 - 6, fieldY1 + inputH * 0.5, "宽度:")
        nvgText(vg, dlgX + dlgW * 0.5 - inputW * 0.5 - 6, fieldY2 + inputH * 0.5, "高度:")

        -- 宽度输入框
        local wInputX = dlgX + dlgW * 0.5 - inputW * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, wInputX, fieldY1, inputW, inputH, 3)
        nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, wInputX, fieldY1, inputW, inputH, 3)
        local wBorderColor = (canvasFocusField == 1) and nvgRGBA(80, 160, 80, 220) or nvgRGBA(60, 60, 80, 200)
        nvgStrokeColor(vg, wBorderColor)
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
        nvgText(vg, wInputX + inputW * 0.5, fieldY1 + inputH * 0.5, canvasWidthInput)

        -- 宽度输入框光标
        if canvasFocusField == 1 and math.floor(renameBlink * 2) % 2 == 0 then
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local textBeforeCursor = string.sub(canvasWidthInput, 1, canvasCursor)
            local bounds = {}
            local tw = nvgTextBounds(vg, 0, 0, textBeforeCursor, bounds)
            -- 居中偏移
            local fullBounds = {}
            local fullW = nvgTextBounds(vg, 0, 0, canvasWidthInput, fullBounds)
            local textStartX = wInputX + (inputW - fullW) * 0.5
            local cursorDrawX = textStartX + tw
            nvgBeginPath(vg)
            nvgMoveTo(vg, cursorDrawX, fieldY1 + 3)
            nvgLineTo(vg, cursorDrawX, fieldY1 + inputH - 3)
            nvgStrokeColor(vg, nvgRGBA(200, 255, 200, 255))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- 高度输入框
        local hInputX = wInputX
        nvgBeginPath(vg)
        nvgRoundedRect(vg, hInputX, fieldY2, inputW, inputH, 3)
        nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, hInputX, fieldY2, inputW, inputH, 3)
        local hBorderColor = (canvasFocusField == 2) and nvgRGBA(80, 160, 80, 220) or nvgRGBA(60, 60, 80, 200)
        nvgStrokeColor(vg, hBorderColor)
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
        nvgText(vg, hInputX + inputW * 0.5, fieldY2 + inputH * 0.5, canvasHeightInput)

        -- 高度输入框光标
        if canvasFocusField == 2 and math.floor(renameBlink * 2) % 2 == 0 then
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local textBeforeCursor = string.sub(canvasHeightInput, 1, canvasCursor)
            local bounds = {}
            local tw = nvgTextBounds(vg, 0, 0, textBeforeCursor, bounds)
            local fullBounds = {}
            local fullW = nvgTextBounds(vg, 0, 0, canvasHeightInput, fullBounds)
            local textStartX = hInputX + (inputW - fullW) * 0.5
            local cursorDrawX = textStartX + tw
            nvgBeginPath(vg)
            nvgMoveTo(vg, cursorDrawX, fieldY2 + 3)
            nvgLineTo(vg, cursorDrawX, fieldY2 + inputH - 3)
            nvgStrokeColor(vg, nvgRGBA(200, 255, 200, 255))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- 格数单位标注
        nvgFontSize(vg, 8)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 160, 180))
        nvgText(vg, wInputX + inputW + 6, fieldY1 + inputH * 0.5, "格")
        nvgText(vg, hInputX + inputW + 6, fieldY2 + inputH * 0.5, "格")

        -- 确认/取消按钮
        local btnW2 = 50
        local btnH2 = 16
        local btnY3 = dlgY + dlgH - btnH2 - 10
        local confirmX = dlgX + dlgW * 0.5 - btnW2 - 6
        local cancelX = dlgX + dlgW * 0.5 + 6

        nvgBeginPath(vg)
        nvgRoundedRect(vg, confirmX, btnY3, btnW2, btnH2, 3)
        nvgFillColor(vg, nvgRGBA(40, 120, 60, 255))
        nvgFill(vg)
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 255, 240, 255))
        nvgText(vg, confirmX + btnW2 * 0.5, btnY3 + btnH2 * 0.5, "确认")

        nvgBeginPath(vg)
        nvgRoundedRect(vg, cancelX, btnY3, btnW2, btnH2, 3)
        nvgFillColor(vg, nvgRGBA(80, 70, 70, 255))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
        nvgText(vg, cancelX + btnW2 * 0.5, btnY3 + btnH2 * 0.5, "取消")

    elseif dialogMode == "player" then
        -- 标题
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 200, 80, 255))
        nvgText(vg, dlgX + dlgW * 0.5, dlgY + 14, "玩家参数")

        -- 4个输入字段
        local inputW = 50
        local inputH = 14
        local startY = dlgY + 28
        local rowGap = 20

        for i = 1, 4 do
            local fieldY = startY + (i - 1) * rowGap

            -- 标签
            nvgFontSize(vg, 9)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
            nvgText(vg, dlgX + dlgW * 0.5 - inputW * 0.5 - 6, fieldY + inputH * 0.5, PLAYER_PARAM_LABELS[i])

            -- 输入框背景
            local inputX = dlgX + dlgW * 0.5 - inputW * 0.5
            nvgBeginPath(vg)
            nvgRoundedRect(vg, inputX, fieldY, inputW, inputH, 3)
            nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
            nvgFill(vg)

            -- 输入框边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, inputX, fieldY, inputW, inputH, 3)
            local borderColor = (playerParamFocus == i) and nvgRGBA(200, 160, 50, 220) or nvgRGBA(60, 60, 80, 200)
            nvgStrokeColor(vg, borderColor)
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 输入文本
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
            nvgText(vg, inputX + inputW * 0.5, fieldY + inputH * 0.5, playerParamInputs[i])

            -- 光标
            if playerParamFocus == i and math.floor(renameBlink * 2) % 2 == 0 then
                nvgFontSize(vg, 10)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                local textBeforeCursor = string.sub(playerParamInputs[i], 1, playerParamCursor)
                local bounds = {}
                local tw = nvgTextBounds(vg, 0, 0, textBeforeCursor, bounds)
                local fullBounds = {}
                local fullW = nvgTextBounds(vg, 0, 0, playerParamInputs[i], fullBounds)
                local textStartX = inputX + (inputW - fullW) * 0.5
                local cursorDrawX = textStartX + tw
                nvgBeginPath(vg)
                nvgMoveTo(vg, cursorDrawX, fieldY + 2)
                nvgLineTo(vg, cursorDrawX, fieldY + inputH - 2)
                nvgStrokeColor(vg, nvgRGBA(255, 220, 100, 255))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end
        end

        -- 确认/取消按钮
        local btnW2 = 50
        local btnH2 = 16
        local btnY3 = dlgY + dlgH - btnH2 - 10
        local confirmX = dlgX + dlgW * 0.5 - btnW2 - 6
        local cancelX = dlgX + dlgW * 0.5 + 6

        nvgBeginPath(vg)
        nvgRoundedRect(vg, confirmX, btnY3, btnW2, btnH2, 3)
        nvgFillColor(vg, nvgRGBA(40, 120, 60, 255))
        nvgFill(vg)
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 255, 240, 255))
        nvgText(vg, confirmX + btnW2 * 0.5, btnY3 + btnH2 * 0.5, "确认")

        nvgBeginPath(vg)
        nvgRoundedRect(vg, cancelX, btnY3, btnW2, btnH2, 3)
        nvgFillColor(vg, nvgRGBA(80, 70, 70, 255))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
        nvgText(vg, cancelX + btnW2 * 0.5, btnY3 + btnH2 * 0.5, "取消")

    elseif dialogMode == "light" then
        -- 标题
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgText(vg, dlgX + dlgW * 0.5, dlgY + 14, "光源参数")

        -- 提示
        nvgFontSize(vg, 8)
        nvgFillColor(vg, nvgRGBA(140, 140, 160, 200))
        nvgText(vg, dlgX + dlgW * 0.5, dlgY + 26, "直径:2~30格  羽化:0.0~1.0")

        -- 直径/羽化两个字段
        local inputW = 50
        local inputH = 16
        local fieldY1 = dlgY + 34
        local fieldY2 = dlgY + 56

        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
        nvgText(vg, dlgX + dlgW * 0.5 - inputW * 0.5 - 6, fieldY1 + inputH * 0.5, "直径:")
        nvgText(vg, dlgX + dlgW * 0.5 - inputW * 0.5 - 6, fieldY2 + inputH * 0.5, "羽化:")

        -- 直径输入框
        local dInputX = dlgX + dlgW * 0.5 - inputW * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, dInputX, fieldY1, inputW, inputH, 3)
        nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, dInputX, fieldY1, inputW, inputH, 3)
        local dBorder = (lightDialogFocus == 1) and nvgRGBA(255, 200, 50, 220) or nvgRGBA(60, 60, 80, 200)
        nvgStrokeColor(vg, dBorder)
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
        nvgText(vg, dInputX + inputW * 0.5, fieldY1 + inputH * 0.5, lightDiameterInput)

        -- 直径光标
        if lightDialogFocus == 1 and math.floor(renameBlink * 2) % 2 == 0 then
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local tbc = string.sub(lightDiameterInput, 1, lightDialogCursor)
            local bounds = {}
            local tw = nvgTextBounds(vg, 0, 0, tbc, bounds)
            local fullBounds = {}
            local fullW = nvgTextBounds(vg, 0, 0, lightDiameterInput, fullBounds)
            local textStartX = dInputX + (inputW - fullW) * 0.5
            nvgBeginPath(vg)
            nvgMoveTo(vg, textStartX + tw, fieldY1 + 3)
            nvgLineTo(vg, textStartX + tw, fieldY1 + inputH - 3)
            nvgStrokeColor(vg, nvgRGBA(255, 220, 100, 255))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- 羽化输入框
        local fInputX = dInputX
        nvgBeginPath(vg)
        nvgRoundedRect(vg, fInputX, fieldY2, inputW, inputH, 3)
        nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, fInputX, fieldY2, inputW, inputH, 3)
        local fBorder = (lightDialogFocus == 2) and nvgRGBA(255, 200, 50, 220) or nvgRGBA(60, 60, 80, 200)
        nvgStrokeColor(vg, fBorder)
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
        nvgText(vg, fInputX + inputW * 0.5, fieldY2 + inputH * 0.5, lightFeatherInput)

        -- 羽化光标
        if lightDialogFocus == 2 and math.floor(renameBlink * 2) % 2 == 0 then
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local tbc = string.sub(lightFeatherInput, 1, lightDialogCursor)
            local bounds = {}
            local tw = nvgTextBounds(vg, 0, 0, tbc, bounds)
            local fullBounds = {}
            local fullW = nvgTextBounds(vg, 0, 0, lightFeatherInput, fullBounds)
            local textStartX = fInputX + (inputW - fullW) * 0.5
            nvgBeginPath(vg)
            nvgMoveTo(vg, textStartX + tw, fieldY2 + 3)
            nvgLineTo(vg, textStartX + tw, fieldY2 + inputH - 3)
            nvgStrokeColor(vg, nvgRGBA(255, 220, 100, 255))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- 单位标注
        nvgFontSize(vg, 8)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 160, 180))
        nvgText(vg, dInputX + inputW + 6, fieldY1 + inputH * 0.5, "格")

        -- 确认/取消按钮
        local btnW2 = 50
        local btnH2 = 16
        local btnY3 = dlgY + dlgH - btnH2 - 10
        local confirmX = dlgX + dlgW * 0.5 - btnW2 - 6
        local cancelX = dlgX + dlgW * 0.5 + 6

        nvgBeginPath(vg)
        nvgRoundedRect(vg, confirmX, btnY3, btnW2, btnH2, 3)
        nvgFillColor(vg, nvgRGBA(40, 120, 60, 255))
        nvgFill(vg)
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 255, 240, 255))
        nvgText(vg, confirmX + btnW2 * 0.5, btnY3 + btnH2 * 0.5, "确认")

        nvgBeginPath(vg)
        nvgRoundedRect(vg, cancelX, btnY3, btnW2, btnH2, 3)
        nvgFillColor(vg, nvgRGBA(80, 70, 70, 255))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
        nvgText(vg, cancelX + btnW2 * 0.5, btnY3 + btnH2 * 0.5, "取消")
    end
end

function DrawMapGrid()
    local mapX = 0
    local mapY = TOPBAR_H
    local mapW = screenDesignW - (sidebarOpen and SIDEBAR_W or 0)
    local mapH = screenDesignH - TOPBAR_H - BOTTOMBAR_H

    nvgSave(vg)
    nvgScissor(vg, mapX, mapY, mapW, mapH)

    nvgBeginPath(vg)
    nvgRect(vg, mapX, mapY, mapW, mapH)
    nvgFillColor(vg, nvgRGBA(15, 12, 25, 255))
    nvgFill(vg)

    -- 计算缩放后的格子尺寸
    local zGrid = GRID * zoomLevel

    -- 可见范围（考虑 zoom 和 cameraY）
    local startCol = math.max(1, math.floor(cameraX / zGrid) + 1)
    local endCol = math.min(MAP_COLS, startCol + math.ceil(mapW / zGrid) + 2)
    local startRow = math.max(1, math.floor(cameraY / zGrid) + 1)
    local endRow = math.min(MAP_ROWS, startRow + math.ceil(mapH / zGrid) + 2)

    -- 网格线
    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        local x = mapX + (col - 1) * zGrid - cameraX
        local y1 = mapY + (startRow - 1) * zGrid - cameraY
        local y2 = mapY + endRow * zGrid - cameraY
        nvgMoveTo(vg, x, math.max(mapY, y1))
        nvgLineTo(vg, x, math.min(mapY + mapH, y2))
    end
    for row = startRow, endRow + 1 do
        local y = mapY + (row - 1) * zGrid - cameraY
        local x1 = mapX + (startCol - 1) * zGrid - cameraX
        local x2 = mapX + endCol * zGrid - cameraX
        nvgMoveTo(vg, math.max(mapX, x1), y)
        nvgLineTo(vg, math.min(mapX + mapW, x2), y)
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 20))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- 地块
    for row = startRow, endRow do
        if not levelData[row] then goto continueRow end
        for col = startCol, endCol do
            local val = levelData[row][col]
            if not val or val == TILE.EMPTY then goto continueEdit end
            local px = mapX + (col - 1) * zGrid - cameraX
            local py = mapY + (row - 1) * zGrid - cameraY
            local base, group = GetTileType(val)

            if base == TILE.SOLID then
                nvgBeginPath(vg)
                nvgRect(vg, px + 0.5, py + 0.5, zGrid - 1, zGrid - 1)
                nvgFillColor(vg, nvgRGBA(55, 60, 75, 255))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, px + 0.5, py + 0.5, zGrid - 1, 2)
                nvgFillColor(vg, nvgRGBA(80, 90, 105, 255))
                nvgFill(vg)
            elseif base == TILE.SPAWN then
                nvgBeginPath(vg)
                nvgRect(vg, px, py, zGrid, zGrid)
                nvgFillColor(vg, nvgRGBA(60, 40, 10, 150))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgMoveTo(vg, px + zGrid * 0.5, py + 2)
                nvgLineTo(vg, px + zGrid - 3, py + zGrid - 2)
                nvgLineTo(vg, px + 3, py + zGrid - 2)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(255, 180, 40, 255))
                nvgFill(vg)
            elseif base == TILE.FUEL then
                nvgBeginPath(vg)
                nvgCircle(vg, px + zGrid * 0.5, py + zGrid * 0.5, 6 * zoomLevel)
                nvgFillColor(vg, nvgRGBA(255, 80, 10, 255))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgCircle(vg, px + zGrid * 0.5, py + zGrid * 0.5, 3 * zoomLevel)
                nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
                nvgFill(vg)
            elseif base == TILE.GOAL then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, px + 2, py + 1, zGrid - 4, zGrid - 2, 2)
                nvgFillColor(vg, nvgRGBA(40, 180, 40, 200))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, px + 2, py + 1, zGrid - 4, zGrid - 2, 2)
                nvgStrokeColor(vg, nvgRGBA(100, 255, 100, 255))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            elseif base == TILE.SPIKE then
                nvgBeginPath(vg)
                nvgMoveTo(vg, px + 2, py + zGrid - 2)
                nvgLineTo(vg, px + zGrid * 0.5, py + 2)
                nvgLineTo(vg, px + zGrid - 2, py + zGrid - 2)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(200, 30, 30, 255))
                nvgFill(vg)
            elseif base == TILE.SWITCH then
                local gc = GROUP_COLORS[group] or GROUP_COLORS[1]
                nvgBeginPath(vg)
                nvgCircle(vg, px + zGrid * 0.5, py + zGrid * 0.5, 5 * zoomLevel)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, px + zGrid * 0.5 - 1, py + 3, 2, 5 * zoomLevel)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
                nvgFill(vg)
            elseif base == TILE.GATE then
                local gc = GROUP_COLORS[group] or GROUP_COLORS[1]
                nvgBeginPath(vg)
                nvgRect(vg, px + 1, py, zGrid - 2, zGrid)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 180))
                nvgFill(vg)
                for dx = 0, 2 do
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 3 + dx * 5 * zoomLevel, py + 2, 2, zGrid - 4)
                    nvgFillColor(vg, nvgRGBA(
                        math.floor(gc[1] * 0.4),
                        math.floor(gc[2] * 0.4),
                        math.floor(gc[3] * 0.4), 255))
                    nvgFill(vg)
                end
            elseif base == TILE.HIDDEN_WALL then
                -- 隐藏墙：编辑器模式下用颜色+组号显示
                -- 颜色随组号加深（darken factor）
                local darken = math.max(0.3, 1.0 - (group - 1) * 0.12)
                local hr = math.floor(hiddenWall.baseColor[1] * darken)
                local hg = math.floor(hiddenWall.baseColor[2] * darken)
                local hb = math.floor(hiddenWall.baseColor[3] * darken)
                -- 背景方块（虚线边框风格）
                nvgBeginPath(vg)
                nvgRect(vg, px + 1, py + 1, zGrid - 2, zGrid - 2)
                nvgFillColor(vg, nvgRGBA(hr, hg, hb, 160))
                nvgFill(vg)
                -- 虚线边框
                nvgBeginPath(vg)
                nvgRect(vg, px + 1, py + 1, zGrid - 2, zGrid - 2)
                nvgStrokeColor(vg, nvgRGBA(hr, hg, hb, 255))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
                -- 组号数字
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.max(7, 9 * zoomLevel))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
                nvgText(vg, px + zGrid * 0.5, py + zGrid * 0.5, tostring(group))
            end

            ::continueEdit::
        end
        ::continueRow::
    end

    -- ================================================================
    -- 摄像机边界框绘制
    -- ================================================================
    local bx1, by1 = GridToScreen(camBound.left, camBound.top)
    local bx2, by2 = GridToScreen(camBound.right + 1, camBound.bottom + 1)

    -- 边界外区域半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, mapX, mapY, mapW, mapH)
    -- 挖空边界内部
    nvgPathWinding(vg, NVG_HOLE)
    local cbx1 = math.max(mapX, bx1)
    local cby1 = math.max(mapY, by1)
    local cbx2 = math.min(mapX + mapW, bx2)
    local cby2 = math.min(mapY + mapH, by2)
    if cbx2 > cbx1 and cby2 > cby1 then
        nvgRect(vg, cbx1, cby1, cbx2 - cbx1, cby2 - cby1)
    end
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
    nvgFill(vg)

    -- 边界虚线框
    nvgBeginPath(vg)
    nvgRect(vg, bx1, by1, bx2 - bx1, by2 - by1)
    nvgStrokeColor(vg, nvgRGBA(0, 200, 255, 200))
    nvgStrokeWidth(vg, 2.0)
    nvgStroke(vg)

    -- 四个角的拖拽指示小方块
    local handleSize = 5
    local corners = {
        {bx1, by1}, {bx2, by1}, {bx1, by2}, {bx2, by2},
    }
    for _, c in ipairs(corners) do
        nvgBeginPath(vg)
        nvgRect(vg, c[1] - handleSize, c[2] - handleSize, handleSize * 2, handleSize * 2)
        nvgFillColor(vg, nvgRGBA(0, 200, 255, 255))
        nvgFill(vg)
    end

    -- 边界尺寸标注
    local boundW = camBound.right - camBound.left + 1
    local boundH = camBound.bottom - camBound.top + 1
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(0, 200, 255, 220))
    nvgText(vg, (bx1 + bx2) * 0.5, by1 - 3, boundW .. "x" .. boundH)

    -- 光源标记（编辑模式始终显示）
    FogOfWar.SetLightSources(FogOfWar.GetLightSources())
    FogOfWar.DrawLightMarkers(vg, {
        gridSize = GRID,
        offsetX = cameraX,
        offsetY = cameraY,
        zoomLevel = zoomLevel,
        mapX = mapX,
        mapY = mapY,
        selectedIndex = selectedLightIndex,
    })

    -- 战争迷雾（编辑器模式仅在开启时显示）
    if fogShowInEditor then
        FogOfWar.Draw(vg, {
            gridSize = GRID,
            startCol = startCol,
            endCol = endCol,
            startRow = startRow,
            endRow = endRow,
            offsetX = cameraX,
            offsetY = cameraY,
            zoomLevel = zoomLevel,
            mapX = mapX,
            mapY = mapY,
        })
    end

    -- ================================================================
    -- 选中高亮 & 拖拽预览
    -- ================================================================
    -- 多选高亮
    if #selectedTiles > 0 and not moveDragging then
        local pulse = math.abs(math.sin(os.clock() * 3.0))
        local alpha = math.floor(140 + pulse * 115)
        for _, sel in ipairs(selectedTiles) do
            local sx, sy = GridToScreen(sel.col, sel.row)
            nvgBeginPath(vg)
            nvgRect(vg, sx - 1, sy - 1, zGrid + 2, zGrid + 2)
            if sel.isLight then
                nvgStrokeColor(vg, nvgRGBA(255, 220, 50, alpha))
            else
                nvgStrokeColor(vg, nvgRGBA(50, 200, 255, alpha))
            end
            nvgStrokeWidth(vg, 2.0)
            nvgStroke(vg)
            -- 内部半透明填充
            nvgBeginPath(vg)
            nvgRect(vg, sx, sy, zGrid, zGrid)
            if sel.isLight then
                nvgFillColor(vg, nvgRGBA(255, 220, 50, 30))
            else
                nvgFillColor(vg, nvgRGBA(50, 200, 255, 30))
            end
            nvgFill(vg)
        end
    elseif selectedTileCol > 0 and selectedTileRow > 0 and not moveDragging then
        -- 单选兼容（selectedTiles 为空时的旧逻辑）
        local sx, sy = GridToScreen(selectedTileCol, selectedTileRow)
        local pulse = math.abs(math.sin(os.clock() * 3.0))
        local alpha = math.floor(140 + pulse * 115)
        nvgBeginPath(vg)
        nvgRect(vg, sx - 1, sy - 1, zGrid + 2, zGrid + 2)
        if selectedIsLight then
            nvgStrokeColor(vg, nvgRGBA(255, 220, 50, alpha))
        else
            nvgStrokeColor(vg, nvgRGBA(50, 200, 255, alpha))
        end
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgRect(vg, sx, sy, zGrid, zGrid)
        if selectedIsLight then
            nvgFillColor(vg, nvgRGBA(255, 220, 50, 30))
        else
            nvgFillColor(vg, nvgRGBA(50, 200, 255, 30))
        end
        nvgFill(vg)
    end

    -- 框选矩形绘制
    if boxSelectActive then
        local bsDx = math.abs(boxSelectCurrentX - boxSelectStartX)
        local bsDy = math.abs(boxSelectCurrentY - boxSelectStartY)
        if bsDx > boxSelectThreshold or bsDy > boxSelectThreshold then
            local bsX = math.min(boxSelectStartX, boxSelectCurrentX)
            local bsY = math.min(boxSelectStartY, boxSelectCurrentY)
            local bsW = math.abs(boxSelectCurrentX - boxSelectStartX)
            local bsH = math.abs(boxSelectCurrentY - boxSelectStartY)
            -- 半透明填充
            nvgBeginPath(vg)
            nvgRect(vg, bsX, bsY, bsW, bsH)
            nvgFillColor(vg, nvgRGBA(80, 160, 255, 30))
            nvgFill(vg)
            -- 虚线边框
            nvgBeginPath(vg)
            nvgRect(vg, bsX, bsY, bsW, bsH)
            nvgStrokeColor(vg, nvgRGBA(80, 180, 255, 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end

    if moveDragging and moveDragCurrentCol > 0 and moveDragCurrentRow > 0 then
        if multiMoving and #selectedTiles > 0 then
            -- 多选拖拽预览
            local offsetCol = moveDragCurrentCol - moveDragStartCol
            local offsetRow = moveDragCurrentRow - moveDragStartRow
            -- 检查是否全部可放置
            local selectedSet = {}
            for _, st in ipairs(selectedTiles) do
                selectedSet[st.row * 10000 + st.col] = true
            end
            local canPlaceAll = true
            if offsetCol ~= 0 or offsetRow ~= 0 then
                for _, st in ipairs(selectedTiles) do
                    local nc = st.col + offsetCol
                    local nr = st.row + offsetRow
                    if nc < 1 or nc > MAP_COLS or nr < 1 or nr > MAP_ROWS then
                        canPlaceAll = false
                        break
                    end
                    if not st.isLight then
                        local destVal = levelData[nr] and levelData[nr][nc]
                        if destVal and destVal ~= TILE.EMPTY and not selectedSet[nr * 10000 + nc] then
                            canPlaceAll = false
                            break
                        end
                    end
                end
            end
            -- 绘制每个选中物体的原位置和目标位置
            for _, st in ipairs(selectedTiles) do
                -- 原位置虚线框
                local ox, oy = GridToScreen(st.col, st.row)
                nvgBeginPath(vg)
                nvgRect(vg, ox, oy, zGrid, zGrid)
                nvgStrokeColor(vg, nvgRGBA(255, 100, 100, 120))
                nvgStrokeWidth(vg, 1.0)
                nvgStroke(vg)
                -- 目标位置预览
                local nc = st.col + offsetCol
                local nr = st.row + offsetRow
                if nc >= 1 and nc <= MAP_COLS and nr >= 1 and nr <= MAP_ROWS then
                    local tx, ty = GridToScreen(nc, nr)
                    nvgBeginPath(vg)
                    nvgRect(vg, tx, ty, zGrid, zGrid)
                    if canPlaceAll then
                        nvgFillColor(vg, nvgRGBA(50, 255, 120, 60))
                    else
                        nvgFillColor(vg, nvgRGBA(255, 60, 60, 60))
                    end
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgRect(vg, tx, ty, zGrid, zGrid)
                    if canPlaceAll then
                        nvgStrokeColor(vg, nvgRGBA(50, 255, 120, 200))
                    else
                        nvgStrokeColor(vg, nvgRGBA(255, 60, 60, 200))
                    end
                    nvgStrokeWidth(vg, 1.5)
                    nvgStroke(vg)
                end
            end
        else
            -- 单选拖拽预览（原逻辑）
            local ox, oy = GridToScreen(moveDragStartCol, moveDragStartRow)
            nvgBeginPath(vg)
            nvgRect(vg, ox, oy, zGrid, zGrid)
            nvgStrokeColor(vg, nvgRGBA(255, 100, 100, 120))
            nvgStrokeWidth(vg, 1.0)
            nvgStroke(vg)

            local tx, ty = GridToScreen(moveDragCurrentCol, moveDragCurrentRow)
            nvgBeginPath(vg)
            nvgRect(vg, tx, ty, zGrid, zGrid)
            local canPlace = true
            if moveDragCurrentCol == moveDragStartCol and moveDragCurrentRow == moveDragStartRow then
                canPlace = true
            elseif moveDragLightIdx > 0 then
                canPlace = true
            else
                local destVal = levelData[moveDragCurrentRow] and levelData[moveDragCurrentRow][moveDragCurrentCol]
                if destVal and destVal ~= TILE.EMPTY then canPlace = false end
            end

            if canPlace then
                nvgFillColor(vg, nvgRGBA(50, 255, 120, 60))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, tx, ty, zGrid, zGrid)
                nvgStrokeColor(vg, nvgRGBA(50, 255, 120, 200))
            else
                nvgFillColor(vg, nvgRGBA(255, 60, 60, 60))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, tx, ty, zGrid, zGrid)
                nvgStrokeColor(vg, nvgRGBA(255, 60, 60, 200))
            end
            nvgStrokeWidth(vg, 2.0)
            nvgStroke(vg)
        end
    end

    -- 悬停指示器
    local mx = input:GetMousePosition().x / dpr / scaleF
    local my = input:GetMousePosition().y / dpr / scaleF
    local hoverCol, hoverRow = ScreenToGrid(mx, my)
    if hoverCol >= 1 and hoverCol <= MAP_COLS and hoverRow >= 1 and hoverRow <= MAP_ROWS then
        local hx, hy = GridToScreen(hoverCol, hoverRow)
        nvgBeginPath(vg)
        nvgRect(vg, hx, hy, zGrid, zGrid)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 120))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 8)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 180))
        nvgText(vg, hx + 1, hy - 1, hoverCol .. "," .. hoverRow)
    end

    -- 缩放比例指示
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 180))
    nvgText(vg, mapW - 4, mapY + mapH - 3, math.floor(zoomLevel * 100) .. "%")

    nvgRestore(vg)
end

-- ====================================================================
-- 分辨率
-- ====================================================================
function RecalcLayout()
    physW, physH = graphics:GetWidth(), graphics:GetHeight()
    dpr = graphics:GetDPR()
    logicalW, logicalH = physW / dpr, physH / dpr
    scaleF = math.min(logicalW / DESIGN_W, logicalH / DESIGN_H)
    screenDesignW = logicalW / scaleF
    screenDesignH = logicalH / scaleF
end

-- ====================================================================
-- 入口
-- ====================================================================
function Start()
    print("=== Level Editor v2 (with Play Mode) ===")
    RecalcLayout()

    vg = nvgCreate(1)
    if not vg then print("ERROR: nvgCreate failed"); return end
    if nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf") == -1 then
        print("ERROR: font load failed"); return
    end

    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    InitEmptyMap()
    InitTopBarButtons()

    -- 从云端加载关卡数据（异步），完成后刷新侧边栏
    msgText = "正在加载云存档..."
    msgTimer = 10.0
    CloudStorage.Init(function(ok, err)
        RefreshSavedLevels()
        if ok then
            local count = #savedLevels
            if count > 0 then
                msgText = "云存档已加载 (" .. count .. " 个关卡)"
            else
                msgText = "云存档已就绪"
            end
        else
            msgText = "云存档加载失败: " .. (err or "未知错误") .. "（可正常编辑，保存时重试）"
        end
        msgTimer = 3.0

        -- 初始化世界地图编辑器（在 CloudStorage 就绪后）
        CloudStorage.InitWorldMap(function(wmOk)
            WorldMapEditor.Init(vg, function(text, duration)
                msgText = text
                msgTimer = duration or 2.0
            end, function(nodeFile, nodeName)
                -- 双击节点回调：自动保存世界地图，然后切换到关卡编辑模式
                WorldMapEditor.Save()
                AutoSaveBeforeSwitch()
                LoadLevel(nodeFile)
                editorMode = MODE_EDIT
                msgText = "编辑关卡: " .. (nodeName or nodeFile)
                msgTimer = 2.0
            end)
            WorldMapEditor.SetLayout(screenDesignW, screenDesignH, TOPBAR_H, 0, sidebarOpen and SIDEBAR_W or 0)
        end)
    end)

    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")
    SubscribeToEvent("TextInput", "HandleTextInput")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("MouseWheel", "HandleMouseWheel")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")

    print("Level Editor ready. P=play test, Ctrl+S=save, Ctrl+L=load")
end

function Stop()
    if vg then nvgDelete(vg); vg = nil end
end

-- ====================================================================
-- 渲染
-- ====================================================================
function HandleNanoVGRender(eventType, eventData)
    if not vg then return end
    nvgBeginFrame(vg, logicalW, logicalH, dpr)
    nvgScale(vg, scaleF, scaleF)

    if editorMode == MODE_PLAY or editorMode == MODE_WORLDPLAY then
        DrawPlayMode()
    elseif editorMode == MODE_WORLDMAP then
        WorldMapEditor.Draw()
        DrawTopBar()
        DrawSidebar()
    else
        DrawMapGrid()
        DrawToolbar()
        DrawTopBar()
        DrawBottomBar()
        DrawSidebar()
        DrawDialog()
    end

    nvgEndFrame(vg)
end

-- ====================================================================
-- 更新
-- ====================================================================
---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    if msgTimer > 0 then msgTimer = msgTimer - dt end
    if dialogMode == "rename" then renameBlink = renameBlink + dt end

    if editorMode == MODE_PLAY then
        PlayUpdate(dt)
        return
    end

    if editorMode == MODE_WORLDPLAY then
        if worldPlayCooldown > 0 then
            worldPlayCooldown = worldPlayCooldown - dt
        end
        PlayUpdate(dt)
        if play.alive and not play.won then
            WorldPlayCheckBoundary()
        end
        return
    end

    if editorMode == MODE_WORLDMAP then
        local mx = input:GetMousePosition().x / dpr / scaleF
        local my = input:GetMousePosition().y / dpr / scaleF
        WorldMapEditor.UpdateMouse(mx, my)
        WorldMapEditor.Update(dt)
        return
    end

    -- 编辑模式：WASD 移动相机
    local scrollSpeed = 200
    if input:GetKeyDown(KEY_A) and not input:GetKeyDown(KEY_CTRL) then
        cameraX = cameraX - scrollSpeed * dt
    end
    if input:GetKeyDown(KEY_D) and not input:GetKeyDown(KEY_CTRL) then
        cameraX = cameraX + scrollSpeed * dt
    end
    if input:GetKeyDown(KEY_W) and not input:GetKeyDown(KEY_CTRL) then
        cameraY = cameraY - scrollSpeed * dt
    end
    if input:GetKeyDown(KEY_S) and not input:GetKeyDown(KEY_CTRL) then
        cameraY = cameraY + scrollSpeed * dt
    end

    -- 限制相机范围（允许一定范围的自由移动）
    local zGrid = GRID * zoomLevel
    local mapW = screenDesignW - (sidebarOpen and SIDEBAR_W or 0)
    local mapH = screenDesignH - TOPBAR_H - BOTTOMBAR_H
    local maxCamX = math.max(0, MAP_COLS * zGrid - mapW)
    local maxCamY = math.max(0, MAP_ROWS * zGrid - mapH)
    cameraX = math.max(-mapW * 0.3, math.min(cameraX, maxCamX + mapW * 0.3))
    cameraY = math.max(-mapH * 0.3, math.min(cameraY, maxCamY + mapH * 0.3))

    -- 边界拖拽更新
    if boundDragActive then
        local mx = input:GetMousePosition().x / dpr / scaleF
        local my = input:GetMousePosition().y / dpr / scaleF
        -- 将鼠标位置转为网格坐标
        local gridCol, gridRow = ScreenToGrid(mx, my)
        gridCol = math.max(1, math.min(gridCol, MAP_COLS))
        gridRow = math.max(1, math.min(gridRow, MAP_ROWS))

        if boundDragEdge == BOUND_EDGE_RIGHT then
            camBound.right = math.max(camBound.left + 1, gridCol)
        elseif boundDragEdge == BOUND_EDGE_LEFT then
            camBound.left = math.min(camBound.right - 1, gridCol)
        elseif boundDragEdge == BOUND_EDGE_BOTTOM then
            camBound.bottom = math.max(camBound.top + 1, gridRow)
        elseif boundDragEdge == BOUND_EDGE_TOP then
            camBound.top = math.min(camBound.bottom - 1, gridRow)
        end
    end

    -- 移动模式：拖拽位置更新
    if moveDragging then
        local mx = input:GetMousePosition().x / dpr / scaleF
        local my = input:GetMousePosition().y / dpr / scaleF
        local col, row = ScreenToGrid(mx, my)
        col = math.max(1, math.min(MAP_COLS, col))
        row = math.max(1, math.min(MAP_ROWS, row))
        moveDragCurrentCol = col
        moveDragCurrentRow = row
    end

    -- 框选模式：追踪当前鼠标位置
    if boxSelectActive then
        local mx = input:GetMousePosition().x / dpr / scaleF
        local my = input:GetMousePosition().y / dpr / scaleF
        boxSelectCurrentX = mx
        boxSelectCurrentY = my
    end

    -- 拖动绘制/擦除（排除侧边栏和底部工具栏区域，且非边界拖拽时）
    if (isDrawing or isErasing) and not boundDragActive then
        local mx = input:GetMousePosition().x / dpr / scaleF
        local my = input:GetMousePosition().y / dpr / scaleF
        local mapRight = screenDesignW - (sidebarOpen and SIDEBAR_W or 0)
        if mx >= 0 and mx < mapRight and my < screenDesignH - BOTTOMBAR_H then
            local col, row = ScreenToGrid(mx, my)
            if col ~= lastPlacedCol or row ~= lastPlacedRow then
                if col >= 1 and col <= MAP_COLS and row >= 1 and row <= MAP_ROWS then
                    if isDrawing then PlaceTile(col, row)
                    else EraseTile(col, row) end
                    lastPlacedCol = col
                    lastPlacedRow = row
                end
            end
        end
    end

    -- 自动保存延时触发（操作后等待 undo.saveDelay 秒再保存，避免频繁写入）
    if undo.saveTimer > 0 then
        undo.saveTimer = undo.saveTimer - dt
        if undo.saveTimer <= 0 then
            undo.saveTimer = 0
            TryAutoSave()
        end
    end
end

-- ====================================================================
-- 输入
-- ====================================================================
---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if editorMode == MODE_PLAY then
        -- 试玩模式按键
        if key == KEY_ESCAPE then
            editorMode = MODE_EDIT
            msgText = "返回编辑模式"
            msgTimer = 1.5
        elseif key == KEY_R then
            StartPlayMode()  -- 重试
        end
        return
    end

    if editorMode == MODE_WORLDPLAY then
        if key == KEY_ESCAPE then
            editorMode = MODE_WORLDMAP
            WorldMapEditor.SetLayout(screenDesignW, screenDesignH, TOPBAR_H, 0, sidebarOpen and SIDEBAR_W or 0)
            msgText = "返回世界地图编辑"
            msgTimer = 1.5
        elseif key == KEY_R then
            StartWorldPlayMode()  -- 重新开始世界试玩
        end
        return
    end

    if editorMode == MODE_WORLDMAP then
        if key == KEY_ESCAPE then
            editorMode = MODE_EDIT
            msgText = "返回编辑模式"
            msgTimer = 1.5
            return
        end
        WorldMapEditor.HandleKeyDown(key)
        return
    end

    -- 对话框键盘处理
    if dialogMode then
        if key == KEY_ESCAPE then
            dialogMode = nil
            dialogTarget = nil
        elseif key == KEY_RETURN or key == KEY_KP_ENTER then
            if dialogMode == "rename" and dialogTarget and renameInput ~= "" then
                RenameLevel(dialogTarget.file, renameInput)
            elseif dialogMode == "delete" and dialogTarget then
                DeleteLevel(dialogTarget.file)
            elseif dialogMode == "canvas" then
                local newW = tonumber(canvasWidthInput) or MAP_COLS
                local newH = tonumber(canvasHeightInput) or MAP_ROWS
                ResizeCanvas(newW, newH)
            elseif dialogMode == "player" then
                ApplyPlayerParams()
            elseif dialogMode == "light" then
                -- 应用光源参数
                if selectedLightIndex > 0 then
                    local d = tonumber(lightDiameterInput) or 6
                    local f = tonumber(lightFeatherInput) or 0.5
                    FogOfWar.UpdateLight(selectedLightIndex, d, f)
                end
            end
            dialogMode = nil
            dialogTarget = nil
        elseif key == KEY_TAB and dialogMode == "light" then
            -- Tab 切换焦点字段
            if lightDialogFocus == 1 then
                lightDialogFocus = 2
                lightDialogCursor = #lightFeatherInput
            else
                lightDialogFocus = 1
                lightDialogCursor = #lightDiameterInput
            end
            renameBlink = 0
        elseif key == KEY_TAB and dialogMode == "player" then
            -- Tab 切换焦点字段 (4个字段循环)
            playerParamFocus = (playerParamFocus % 4) + 1
            playerParamCursor = #playerParamInputs[playerParamFocus]
            renameBlink = 0
        elseif key == KEY_TAB and dialogMode == "canvas" then
            -- Tab 切换焦点字段
            if canvasFocusField == 1 then
                canvasFocusField = 2
                canvasCursor = #canvasHeightInput
            else
                canvasFocusField = 1
                canvasCursor = #canvasWidthInput
            end
            renameBlink = 0
        elseif dialogMode == "canvas" then
            -- 画布对话框的键盘输入（数字）
            local currentInput = (canvasFocusField == 1) and canvasWidthInput or canvasHeightInput
            if key == KEY_BACKSPACE then
                if canvasCursor > 0 then
                    currentInput = string.sub(currentInput, 1, canvasCursor - 1) .. string.sub(currentInput, canvasCursor + 1)
                    canvasCursor = canvasCursor - 1
                    renameBlink = 0
                end
            elseif key == KEY_DELETE then
                if canvasCursor < #currentInput then
                    currentInput = string.sub(currentInput, 1, canvasCursor) .. string.sub(currentInput, canvasCursor + 2)
                    renameBlink = 0
                end
            elseif key == KEY_LEFT then
                canvasCursor = math.max(0, canvasCursor - 1)
                renameBlink = 0
            elseif key == KEY_RIGHT then
                canvasCursor = math.min(#currentInput, canvasCursor + 1)
                renameBlink = 0
            elseif key == KEY_HOME then
                canvasCursor = 0
                renameBlink = 0
            elseif key == KEY_END then
                canvasCursor = #currentInput
                renameBlink = 0
            end
            -- 回写
            if canvasFocusField == 1 then
                canvasWidthInput = currentInput
            else
                canvasHeightInput = currentInput
            end
        elseif dialogMode == "player" then
            -- 玩家参数对话框的键盘输入
            local currentInput = playerParamInputs[playerParamFocus]
            if key == KEY_BACKSPACE then
                if playerParamCursor > 0 then
                    currentInput = string.sub(currentInput, 1, playerParamCursor - 1) .. string.sub(currentInput, playerParamCursor + 1)
                    playerParamCursor = playerParamCursor - 1
                    renameBlink = 0
                end
            elseif key == KEY_DELETE then
                if playerParamCursor < #currentInput then
                    currentInput = string.sub(currentInput, 1, playerParamCursor) .. string.sub(currentInput, playerParamCursor + 2)
                    renameBlink = 0
                end
            elseif key == KEY_LEFT then
                playerParamCursor = math.max(0, playerParamCursor - 1)
                renameBlink = 0
            elseif key == KEY_RIGHT then
                playerParamCursor = math.min(#currentInput, playerParamCursor + 1)
                renameBlink = 0
            elseif key == KEY_HOME then
                playerParamCursor = 0
                renameBlink = 0
            elseif key == KEY_END then
                playerParamCursor = #currentInput
                renameBlink = 0
            end
            playerParamInputs[playerParamFocus] = currentInput
        elseif dialogMode == "light" then
            -- 光源对话框的键盘输入
            local currentInput = (lightDialogFocus == 1) and lightDiameterInput or lightFeatherInput
            if key == KEY_BACKSPACE then
                if lightDialogCursor > 0 then
                    currentInput = string.sub(currentInput, 1, lightDialogCursor - 1) .. string.sub(currentInput, lightDialogCursor + 1)
                    lightDialogCursor = lightDialogCursor - 1
                    renameBlink = 0
                end
            elseif key == KEY_DELETE then
                if lightDialogCursor < #currentInput then
                    currentInput = string.sub(currentInput, 1, lightDialogCursor) .. string.sub(currentInput, lightDialogCursor + 2)
                    renameBlink = 0
                end
            elseif key == KEY_LEFT then
                lightDialogCursor = math.max(0, lightDialogCursor - 1)
                renameBlink = 0
            elseif key == KEY_RIGHT then
                lightDialogCursor = math.min(#currentInput, lightDialogCursor + 1)
                renameBlink = 0
            elseif key == KEY_HOME then
                lightDialogCursor = 0
                renameBlink = 0
            elseif key == KEY_END then
                lightDialogCursor = #currentInput
                renameBlink = 0
            end
            -- 回写
            if lightDialogFocus == 1 then
                lightDiameterInput = currentInput
            else
                lightFeatherInput = currentInput
            end
        elseif dialogMode == "rename" then
            if key == KEY_BACKSPACE then
                if renameCursor > 0 then
                    -- UTF-8 安全删除：从 renameCursor 往回找一个字符的起始
                    local pos = renameCursor
                    while pos > 0 do
                        pos = pos - 1
                        local byte = string.byte(renameInput, pos + 1) or 0
                        -- UTF-8 续字节以 10xxxxxx 开头
                        if byte < 0x80 or byte >= 0xC0 then break end
                    end
                    renameInput = string.sub(renameInput, 1, pos) .. string.sub(renameInput, renameCursor + 1)
                    renameCursor = pos
                    renameBlink = 0
                end
            elseif key == KEY_DELETE then
                if renameCursor < #renameInput then
                    -- 找到下一个字符的结尾
                    local pos = renameCursor + 1
                    while pos < #renameInput do
                        local nextByte = string.byte(renameInput, pos + 1) or 0
                        if nextByte < 0x80 or nextByte >= 0xC0 then break end
                        pos = pos + 1
                    end
                    renameInput = string.sub(renameInput, 1, renameCursor) .. string.sub(renameInput, pos + 1)
                    renameBlink = 0
                end
            elseif key == KEY_LEFT then
                if renameCursor > 0 then
                    local pos = renameCursor - 1
                    while pos > 0 do
                        local byte = string.byte(renameInput, pos + 1) or 0
                        if byte < 0x80 or byte >= 0xC0 then break end
                        pos = pos - 1
                    end
                    renameCursor = pos
                    renameBlink = 0
                end
            elseif key == KEY_RIGHT then
                if renameCursor < #renameInput then
                    local pos = renameCursor + 1
                    while pos < #renameInput do
                        local nextByte = string.byte(renameInput, pos + 1) or 0
                        if nextByte < 0x80 or nextByte >= 0xC0 then break end
                        pos = pos + 1
                    end
                    renameCursor = pos
                    renameBlink = 0
                end
            elseif key == KEY_HOME then
                renameCursor = 0
                renameBlink = 0
            elseif key == KEY_END then
                renameCursor = #renameInput
                renameBlink = 0
            end
        end
        return  -- 对话框激活时不处理其他按键
    end

    -- 交互模式快捷键（R=绘制, Q=选取, E=移动）
    if key == KEY_R then
        interactMode = INTERACT_DRAW
        ClearSelection()
        msgText = "模式: 绘制"
        msgTimer = 1.0
    elseif key == KEY_Q then
        interactMode = INTERACT_SELECT
        msgText = "模式: 选取"
        msgTimer = 1.0
    elseif key == KEY_E then
        interactMode = INTERACT_MOVE
        msgText = "模式: 移动"
        msgTimer = 1.0
    end

    -- 编辑模式按键
    if key >= KEY_1 and key <= KEY_9 then
        local idx = key - KEY_1 + 1
        if idx <= #TOOLS then
            local prevTool = currentTool
            currentTool = idx
            interactMode = INTERACT_DRAW  -- 选工具自动切回绘制模式
            -- 隐藏墙工具切换逻辑：从其他工具切回隐藏墙时，组号+1
            local hiddenWallToolIdx = 8  -- HIDDEN_WALL 在 TOOLS 中的索引
            if idx == hiddenWallToolIdx and prevTool ~= hiddenWallToolIdx then
                hiddenWall.group = hiddenWall.group + 1
                hiddenWall.lastEditTime = 0  -- 重置计时
            end
        end
    end

    -- F 键切换编辑器迷雾显示
    if key == KEY_F then
        fogShowInEditor = not fogShowInEditor
        msgText = fogShowInEditor and "迷雾: 开启" or "迷雾: 关闭"
        msgTimer = 1.5
    end

    if key == KEY_G then
        currentGroup = currentGroup % MAX_GROUPS + 1
        msgText = "颜色组:" .. GROUP_NAMES[currentGroup]
        msgTimer = 1.5
    end

    if key == KEY_T then
        CycleDifficulty()
    end

    if key == KEY_P then
        AutoSaveBeforeSwitch()
        StartPlayMode()
    end

    if key == KEY_Z then
        Undo()
    end

    if key == KEY_S and input:GetKeyDown(KEY_CTRL) then
        SaveLevel()
        undo.dirty = false
    end
    if key == KEY_L and input:GetKeyDown(KEY_CTRL) then
        sidebarOpen = not sidebarOpen
    end

    if key == KEY_ESCAPE then
        AutoSaveBeforeSwitch()
        engine:Exit()
    end
end

function HandleKeyUp(eventType, eventData)
end

---@param eventType string
---@param eventData TextInputEventData
function HandleTextInput(eventType, eventData)
    if dialogMode == "rename" then
        local text = eventData["Text"]:GetString()
        if text and #text > 0 then
            -- 限制最大长度（20个字符左右）
            if #renameInput < 60 then
                renameInput = string.sub(renameInput, 1, renameCursor) .. text .. string.sub(renameInput, renameCursor + 1)
                renameCursor = renameCursor + #text
                renameBlink = 0
            end
        end
    elseif dialogMode == "canvas" then
        local text = eventData["Text"]:GetString()
        if text and #text > 0 then
            -- 只接受数字字符
            local digits = text:match("%d+")
            if digits then
                local currentInput = (canvasFocusField == 1) and canvasWidthInput or canvasHeightInput
                if #currentInput < 4 then  -- 最多4位数
                    currentInput = string.sub(currentInput, 1, canvasCursor) .. digits .. string.sub(currentInput, canvasCursor + 1)
                    canvasCursor = canvasCursor + #digits
                    renameBlink = 0
                    if canvasFocusField == 1 then
                        canvasWidthInput = currentInput
                    else
                        canvasHeightInput = currentInput
                    end
                end
            end
        end
    elseif dialogMode == "player" then
        local text = eventData["Text"]:GetString()
        if text and #text > 0 then
            -- 接受数字和小数点
            local valid = text:match("[%d%.]+")
            if valid then
                local currentInput = playerParamInputs[playerParamFocus]
                if #currentInput < 6 then  -- 最多6字符
                    currentInput = string.sub(currentInput, 1, playerParamCursor) .. valid .. string.sub(currentInput, playerParamCursor + 1)
                    playerParamCursor = playerParamCursor + #valid
                    renameBlink = 0
                    playerParamInputs[playerParamFocus] = currentInput
                end
            end
        end
    elseif dialogMode == "light" then
        local text = eventData["Text"]:GetString()
        if text and #text > 0 then
            -- 接受数字和小数点
            local valid = text:match("[%d%.]+")
            if valid then
                local currentInput = (lightDialogFocus == 1) and lightDiameterInput or lightFeatherInput
                if #currentInput < 5 then  -- 最多5字符
                    currentInput = string.sub(currentInput, 1, lightDialogCursor) .. valid .. string.sub(currentInput, lightDialogCursor + 1)
                    lightDialogCursor = lightDialogCursor + #valid
                    renameBlink = 0
                    if lightDialogFocus == 1 then
                        lightDiameterInput = currentInput
                    else
                        lightFeatherInput = currentInput
                    end
                end
            end
        end
    end
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    if editorMode == MODE_PLAY then
        local button = eventData["Button"]:GetInt()
        if button == MOUSEB_LEFT then
            local mx = input:GetMousePosition().x / dpr / scaleF
            local my = input:GetMousePosition().y / dpr / scaleF
            -- "返回编辑"按钮区域检测（增加点击容差）
            local backBtnW = 50
            local backBtnH = 16
            local backBtnX = screenDesignW - backBtnW - 6
            local backBtnY = (22 - backBtnH) * 0.5
            local pad = 6  -- 额外点击容差
            if mx >= backBtnX - pad and mx < backBtnX + backBtnW + pad and my >= backBtnY - pad and my < backBtnY + backBtnH + pad then
                editorMode = MODE_EDIT
                msgText = "返回编辑模式"
                msgTimer = 1.5
            end
        end
        return
    end

    if editorMode == MODE_WORLDPLAY then
        local button = eventData["Button"]:GetInt()
        if button == MOUSEB_LEFT then
            local mx = input:GetMousePosition().x / dpr / scaleF
            local my = input:GetMousePosition().y / dpr / scaleF
            -- "返回世界地图"按钮区域检测（增加点击容差）
            local backBtnW = 60
            local backBtnH = 16
            local backBtnX = screenDesignW - backBtnW - 6
            local backBtnY = (22 - backBtnH) * 0.5
            local pad = 6
            if mx >= backBtnX - pad and mx < backBtnX + backBtnW + pad and my >= backBtnY - pad and my < backBtnY + backBtnH + pad then
                editorMode = MODE_WORLDMAP
                WorldMapEditor.SetLayout(screenDesignW, screenDesignH, TOPBAR_H, 0, sidebarOpen and SIDEBAR_W or 0)
                msgText = "返回世界地图编辑"
                msgTimer = 1.5
            end
        end
        return
    end

    if editorMode == MODE_WORLDMAP then
        local button = eventData["Button"]:GetInt()
        local mx = input:GetMousePosition().x / dpr / scaleF
        local my = input:GetMousePosition().y / dpr / scaleF

        -- 顶栏按钮在世界地图模式也可用
        if my < TOPBAR_H and button == MOUSEB_LEFT then
            for _, btn in ipairs(topBarButtons) do
                if mx >= btn.x and mx < btn.x + btn.w and my >= btn.y and my < btn.y + btn.h then
                    if btn.id == "worldmap" then
                        editorMode = MODE_EDIT
                        msgText = "返回编辑模式"
                        msgTimer = 1.5
                    elseif btn.id == "play" then
                        StartWorldPlayMode()
                    elseif btn.id == "save" then
                        WorldMapEditor.Save()
                    elseif btn.id == "sidebar" then
                        sidebarOpen = not sidebarOpen
                    end
                    return
                end
            end
            return
        end

        -- 侧边栏点击 → 添加节点到世界地图
        if sidebarOpen and mx >= screenDesignW - SIDEBAR_W and my > TOPBAR_H and my < screenDesignH then
            if button == MOUSEB_LEFT then
                local sbY = TOPBAR_H
                local itemH = 22
                local listY = sbY + 24 - sidebarScroll
                for i, lv in ipairs(savedLevels) do
                    local iy = listY + (i - 1) * itemH
                    if my >= iy and my < iy + itemH then
                        WorldMapEditor.AddNode(lv.file, lv.name)
                        return
                    end
                end
            end
            return
        end

        -- 地图区域交互 → 委托给 WorldMapEditor
        WorldMapEditor.HandleMouseDown(button, mx, my)
        return
    end

    local button = eventData["Button"]:GetInt()
    local mx = input:GetMousePosition().x / dpr / scaleF
    local my = input:GetMousePosition().y / dpr / scaleF

    -- 对话框点击（优先处理，阻塞其他交互）
    if dialogMode and button == MOUSEB_LEFT then
        local dlgW = 180
        local dlgH = 65
        if dialogMode == "rename" then dlgH = 80
        elseif dialogMode == "canvas" then dlgH = 100
        elseif dialogMode == "player" then dlgW = 200; dlgH = 150
        elseif dialogMode == "light" then dlgH = 100 end
        local dlgX = (screenDesignW - dlgW) * 0.5
        local dlgY = (screenDesignH - dlgH) * 0.5

        local btnW2 = 50
        local btnH2 = 16
        local btnY3 = dlgY + dlgH - btnH2 - 10
        local confirmX = dlgX + dlgW * 0.5 - btnW2 - 6
        local cancelX = dlgX + dlgW * 0.5 + 6

        -- 确认按钮
        if mx >= confirmX and mx < confirmX + btnW2 and my >= btnY3 and my < btnY3 + btnH2 then
            if dialogMode == "rename" and dialogTarget then
                if renameInput ~= "" then
                    RenameLevel(dialogTarget.file, renameInput)
                end
            elseif dialogMode == "delete" and dialogTarget then
                DeleteLevel(dialogTarget.file)
            elseif dialogMode == "canvas" then
                local newW = tonumber(canvasWidthInput) or MAP_COLS
                local newH = tonumber(canvasHeightInput) or MAP_ROWS
                ResizeCanvas(newW, newH)
            elseif dialogMode == "player" then
                ApplyPlayerParams()
            elseif dialogMode == "light" then
                if selectedLightIndex > 0 then
                    local d = tonumber(lightDiameterInput) or 6
                    local f = tonumber(lightFeatherInput) or 0.5
                    FogOfWar.UpdateLight(selectedLightIndex, d, f)
                end
            end
            dialogMode = nil
            dialogTarget = nil
            return
        end

        -- 取消按钮
        if mx >= cancelX and mx < cancelX + btnW2 and my >= btnY3 and my < btnY3 + btnH2 then
            dialogMode = nil
            dialogTarget = nil
            return
        end

        -- 画布对话框：点击输入框切换焦点
        if dialogMode == "canvas" then
            local inputW = 50
            local inputH = 16
            local fieldY1 = dlgY + 34
            local fieldY2 = dlgY + 56
            local wInputX = dlgX + dlgW * 0.5 - inputW * 0.5

            if mx >= wInputX and mx < wInputX + inputW and my >= fieldY1 and my < fieldY1 + inputH then
                canvasFocusField = 1
                canvasCursor = #canvasWidthInput
                renameBlink = 0
                return
            end
            if mx >= wInputX and mx < wInputX + inputW and my >= fieldY2 and my < fieldY2 + inputH then
                canvasFocusField = 2
                canvasCursor = #canvasHeightInput
                renameBlink = 0
                return
            end
        end

        -- 光源对话框：点击输入框切换焦点
        if dialogMode == "light" then
            local inputW = 50
            local inputH = 16
            local fieldY1 = dlgY + 34
            local fieldY2 = dlgY + 56
            local dInputX = dlgX + dlgW * 0.5 - inputW * 0.5

            if mx >= dInputX and mx < dInputX + inputW and my >= fieldY1 and my < fieldY1 + inputH then
                lightDialogFocus = 1
                lightDialogCursor = #lightDiameterInput
                renameBlink = 0
                return
            end
            if mx >= dInputX and mx < dInputX + inputW and my >= fieldY2 and my < fieldY2 + inputH then
                lightDialogFocus = 2
                lightDialogCursor = #lightFeatherInput
                renameBlink = 0
                return
            end
        end

        -- 玩家参数对话框：点击输入框切换焦点
        if dialogMode == "player" then
            local inputW = 50
            local inputH = 14
            local startY = dlgY + 28
            local rowGap = 20
            local inputX = dlgX + dlgW * 0.5 - inputW * 0.5

            for i = 1, 4 do
                local fieldY = startY + (i - 1) * rowGap
                if mx >= inputX and mx < inputX + inputW and my >= fieldY and my < fieldY + inputH then
                    playerParamFocus = i
                    playerParamCursor = #playerParamInputs[i]
                    renameBlink = 0
                    return
                end
            end
        end

        -- 点击对话框外部也取消
        if mx < dlgX or mx > dlgX + dlgW or my < dlgY or my > dlgY + dlgH then
            dialogMode = nil
            dialogTarget = nil
        end
        return
    end

    -- 顶栏按钮点击
    if my < TOPBAR_H and button == MOUSEB_LEFT then
        for _, btn in ipairs(topBarButtons) do
            if mx >= btn.x and mx < btn.x + btn.w and my >= btn.y and my < btn.y + btn.h then
                if btn.id == "save" then
                    SaveLevel()
                elseif btn.id == "saveNew" then
                    SaveAsNewLevel()
                elseif btn.id == "canvas" then
                    OpenCanvasDialog()
                elseif btn.id == "player" then
                    OpenPlayerDialog()
                elseif btn.id == "fog" then
                    fogShowInEditor = not fogShowInEditor
                    msgText = fogShowInEditor and "迷雾: 开启" or "迷雾: 关闭"
                    msgTimer = 1.5
                elseif btn.id == "random" then
                    AutoSaveBeforeSwitch()
                    GenerateRandomLevel()
                elseif btn.id == "play" then
                    AutoSaveBeforeSwitch()
                    StartPlayMode()
                elseif btn.id == "worldmap" then
                    AutoSaveBeforeSwitch()
                    editorMode = MODE_WORLDMAP
                    WorldMapEditor.SetLayout(screenDesignW, screenDesignH, TOPBAR_H, 0, sidebarOpen and SIDEBAR_W or 0)
                    msgText = "世界地图编辑模式"
                    msgTimer = 2.0
                elseif btn.id == "sidebar" then
                    sidebarOpen = not sidebarOpen
                end
                return
            end
        end
        return
    end

    -- 侧边栏点击
    if sidebarOpen and mx >= screenDesignW - SIDEBAR_W and my > TOPBAR_H and my < screenDesignH - BOTTOMBAR_H then
        if button == MOUSEB_LEFT then
            local sbX = screenDesignW - SIDEBAR_W
            local sbY = TOPBAR_H
            local itemH = 22
            local listY = sbY + 24 - sidebarScroll
            local actionBtnSize = 14

            for i, lv in ipairs(savedLevels) do
                local iy = listY + (i - 1) * itemH
                if my >= iy and my < iy + itemH then
                    -- 检查是否点击了操作按钮
                    local btnY2 = iy + (itemH - actionBtnSize) * 0.5
                    local delX = sbX + SIDEBAR_W - 8 - actionBtnSize
                    local renX = delX - actionBtnSize - 2

                    -- 删除按钮
                    if mx >= delX and mx < delX + actionBtnSize and my >= btnY2 and my < btnY2 + actionBtnSize then
                        dialogMode = "delete"
                        dialogTarget = lv
                        return
                    end

                    -- 重命名按钮
                    if mx >= renX and mx < renX + actionBtnSize and my >= btnY2 and my < btnY2 + actionBtnSize then
                        dialogMode = "rename"
                        dialogTarget = lv
                        renameInput = lv.name
                        renameCursor = #lv.name
                        renameBlink = 0
                        return
                    end

                    -- 其他区域点击 = 加载关卡
                    AutoSaveBeforeSwitch()
                    LoadLevel(lv.file)
                    return
                end
            end
        end
        return
    end

    -- 底部工具栏点击
    local barY = screenDesignH - BOTTOMBAR_H
    if my >= barY and my < screenDesignH - 16 and button == MOUSEB_LEFT then
        -- 交互模式切换按钮区域检测（竖向排列）
        local modeBtnW = 20
        local modeBtnH = 11
        local modeBtnPad = 2
        local modeBtnStartX = 6
        local modeBtnStartY = barY + 3
        for i = 1, 3 do
            local mbx = modeBtnStartX
            local mby = modeBtnStartY + (i - 1) * (modeBtnH + modeBtnPad)
            if mx >= mbx and mx < mbx + modeBtnW and my >= mby and my < mby + modeBtnH then
                interactMode = i
                if i ~= INTERACT_SELECT and i ~= INTERACT_MOVE then
                    ClearSelection()
                end
                return
            end
        end

        -- 工具按钮区域
        local btnW = 36
        local btnH = 28
        local btnPad = 4
        local totalW = #TOOLS * (btnW + btnPad) - btnPad
        local startX = (screenDesignW - totalW) * 0.5
        local toolBarH = BOTTOMBAR_H - 16
        local btnY = barY + (toolBarH - btnH) * 0.5
        for i = 1, #TOOLS do
            local bx = startX + (i - 1) * (btnW + btnPad)
            if mx >= bx and mx < bx + btnW and my >= btnY and my < btnY + btnH then
                local prevTool = currentTool
                currentTool = i
                interactMode = INTERACT_DRAW  -- 选工具时自动切回绘制模式
                -- 隐藏墙工具切换逻辑
                local hiddenWallToolIdx = 8
                if i == hiddenWallToolIdx and prevTool ~= hiddenWallToolIdx then
                    hiddenWall.group = hiddenWall.group + 1
                    hiddenWall.lastEditTime = 0
                end
                ClearSelection()
                return
            end
        end
        return
    end

    -- 地图区域（排除侧边栏和底部工具栏）
    local mapRight = screenDesignW - (sidebarOpen and SIDEBAR_W or 0)
    if mx >= 0 and mx < mapRight and my >= TOPBAR_H and my < screenDesignH - BOTTOMBAR_H then
        -- 优先检测边界拖拽（仅绘制模式）
        if interactMode == INTERACT_DRAW and button == MOUSEB_LEFT then
            local edge = DetectBoundEdge(mx, my)
            if edge ~= BOUND_EDGE_NONE then
                boundDragActive = true
                boundDragEdge = edge
                return
            end
        end

        local col, row = ScreenToGrid(mx, my)
        if col >= 1 and col <= MAP_COLS and row >= 1 and row <= MAP_ROWS then

            -- ============ 选取模式 ============
            if interactMode == INTERACT_SELECT then
                if button == MOUSEB_LEFT then
                    -- 开始框选追踪（在 MouseUp 中判断是点击还是框选）
                    boxSelectActive = true
                    boxSelectStartX = mx
                    boxSelectStartY = my
                    boxSelectCurrentX = mx
                    boxSelectCurrentY = my
                elseif button == MOUSEB_RIGHT then
                    ClearSelection()
                end
                return

            -- ============ 移动模式 ============
            elseif interactMode == INTERACT_MOVE then
                if button == MOUSEB_LEFT then
                    -- 检查是否点击了多选列表中的物体（多选拖拽）
                    local clickedInMultiSelect = false
                    if #selectedTiles > 0 then
                        for _, st in ipairs(selectedTiles) do
                            if st.col == col and st.row == row then
                                clickedInMultiSelect = true
                                break
                            end
                        end
                    end

                    if clickedInMultiSelect then
                        -- 多选拖拽
                        multiMoving = true
                        moveDragging = true
                        moveDragStartCol = col
                        moveDragStartRow = row
                        moveDragCurrentCol = col
                        moveDragCurrentRow = row
                        moveDragTileValue = 0
                        moveDragLightIdx = 0
                    else
                        -- 单选拖拽（原逻辑）
                        multiMoving = false
                        local lightIdx = FogOfWar.FindLight(col, row)
                        if lightIdx then
                            selectedTileCol = col
                            selectedTileRow = row
                            selectedIsLight = true
                            selectedLightIndex = lightIdx
                            moveDragging = true
                            moveDragStartCol = col
                            moveDragStartRow = row
                            moveDragCurrentCol = col
                            moveDragCurrentRow = row
                            moveDragTileValue = 0
                            moveDragLightIdx = lightIdx
                        elseif IsTileSelectable(col, row) then
                            selectedTileCol = col
                            selectedTileRow = row
                            selectedIsLight = false
                            moveDragging = true
                            moveDragStartCol = col
                            moveDragStartRow = row
                            moveDragCurrentCol = col
                            moveDragCurrentRow = row
                            moveDragTileValue = levelData[row][col]
                            moveDragLightIdx = 0
                        else
                            ClearSelection()
                        end
                    end
                elseif button == MOUSEB_RIGHT then
                    ClearSelection()
                    moveDragging = false
                    multiMoving = false
                end
                return

            -- ============ 绘制模式（原有逻辑） ============
            else
                -- 光源工具特殊处理
                if currentTool == LIGHT_TOOL_INDEX then
                    if button == MOUSEB_LEFT then
                        local existIdx = FogOfWar.FindLight(col, row)
                        if existIdx then
                            selectedLightIndex = existIdx
                            local light = FogOfWar.GetLight(existIdx)
                            lightDiameterInput = tostring(light.diameter)
                            lightFeatherInput = tostring(light.feather)
                            dialogMode = "light"
                            lightDialogFocus = 1
                            lightDialogCursor = #lightDiameterInput
                            renameBlink = 0
                        else
                            local idx = FogOfWar.AddLight(col, row, 6, 0.5)
                            selectedLightIndex = idx
                            lightSources = FogOfWar.GetLightSources()
                            undo.dirty = true
                            undo.saveTimer = undo.saveDelay
                            msgText = "放置光源 (" .. col .. "," .. row .. ")"
                            msgTimer = 1.5
                            local light = FogOfWar.GetLight(idx)
                            lightDiameterInput = tostring(light.diameter)
                            lightFeatherInput = tostring(light.feather)
                            dialogMode = "light"
                            lightDialogFocus = 1
                            lightDialogCursor = #lightDiameterInput
                            renameBlink = 0
                        end
                    elseif button == MOUSEB_RIGHT then
                        local removed = FogOfWar.RemoveLight(col, row)
                        if removed then
                            lightSources = FogOfWar.GetLightSources()
                            selectedLightIndex = 0
                            dialogMode = nil
                            undo.dirty = true
                            undo.saveTimer = undo.saveDelay
                            msgText = "删除光源"
                            msgTimer = 1.5
                        end
                    end
                else
                    -- 普通地块工具
                    if button == MOUSEB_LEFT then
                        isDrawing = true; isErasing = false
                        PlaceTile(col, row)
                        lastPlacedCol = col; lastPlacedRow = row
                    elseif button == MOUSEB_RIGHT then
                        isErasing = true; isDrawing = false
                        EraseTile(col, row)
                        lastPlacedCol = col; lastPlacedRow = row
                    end
                end
            end
        end
    end
end

---@param eventType string
---@param eventData MouseButtonUpEventData
function HandleMouseUp(eventType, eventData)
    if editorMode == MODE_PLAY or editorMode == MODE_WORLDPLAY then return end
    local button = eventData["Button"]:GetInt()
    local mx = input:GetMousePosition().x / dpr / scaleF
    local my = input:GetMousePosition().y / dpr / scaleF

    if editorMode == MODE_WORLDMAP then
        WorldMapEditor.HandleMouseUp(button, mx, my)
        return
    end

    if button == MOUSEB_LEFT then
        -- 选取模式：完成框选或点击选中
        if boxSelectActive then
            boxSelectActive = false
            local dx = math.abs(boxSelectCurrentX - boxSelectStartX)
            local dy = math.abs(boxSelectCurrentY - boxSelectStartY)

            if dx > boxSelectThreshold or dy > boxSelectThreshold then
                -- 框选：收集矩形内所有可选物体
                local c1, r1 = ScreenToGrid(math.min(boxSelectStartX, boxSelectCurrentX), math.min(boxSelectStartY, boxSelectCurrentY))
                local c2, r2 = ScreenToGrid(math.max(boxSelectStartX, boxSelectCurrentX), math.max(boxSelectStartY, boxSelectCurrentY))
                c1 = math.max(1, math.min(MAP_COLS, c1))
                c2 = math.max(1, math.min(MAP_COLS, c2))
                r1 = math.max(1, math.min(MAP_ROWS, r1))
                r2 = math.max(1, math.min(MAP_ROWS, r2))

                -- 当前工具对应的 tile 类型（优先选取）
                local toolTile = TOOLS[currentTool] and TOOLS[currentTool].tile or 0
                local priorityList = {}
                local otherList = {}

                -- 扫描区域内的光源
                local lights = FogOfWar.GetLightSources()
                for idx, lt in ipairs(lights) do
                    if lt.col >= c1 and lt.col <= c2 and lt.row >= r1 and lt.row <= r2 then
                        local entry = { col = lt.col, row = lt.row, isLight = true, lightIdx = idx }
                        if toolTile == -1 then  -- 光源工具
                            priorityList[#priorityList + 1] = entry
                        else
                            otherList[#otherList + 1] = entry
                        end
                    end
                end

                -- 扫描区域内的地块
                for row = r1, r2 do
                    for col = c1, c2 do
                        if IsTileSelectable(col, row) then
                            local val = levelData[row][col]
                            local base = GetTileType(val)
                            local entry = { col = col, row = row, isLight = false, lightIdx = 0 }
                            if base == toolTile then
                                priorityList[#priorityList + 1] = entry
                            else
                                otherList[#otherList + 1] = entry
                            end
                        end
                    end
                end

                -- 优先选取匹配当前工具类型的机关，若没有则选取全部
                if #priorityList > 0 then
                    selectedTiles = priorityList
                else
                    selectedTiles = otherList
                end

                -- 同时设置单选变量为第一个元素（兼容高亮和移动）
                if #selectedTiles > 0 then
                    local first = selectedTiles[1]
                    selectedTileCol = first.col
                    selectedTileRow = first.row
                    selectedIsLight = first.isLight
                    if first.isLight then selectedLightIndex = first.lightIdx end
                    msgText = "框选 " .. #selectedTiles .. " 个物体"
                    msgTimer = 1.5
                else
                    ClearSelection()
                end
            else
                -- 点击选中（小位移视为点击）
                local col, row = ScreenToGrid(boxSelectStartX, boxSelectStartY)
                if col >= 1 and col <= MAP_COLS and row >= 1 and row <= MAP_ROWS then
                    local lightIdx = FogOfWar.FindLight(col, row)
                    if lightIdx then
                        selectedTileCol = col
                        selectedTileRow = row
                        selectedIsLight = true
                        selectedLightIndex = lightIdx
                        selectedTiles = {{ col = col, row = row, isLight = true, lightIdx = lightIdx }}
                        msgText = "选中光源 (" .. col .. "," .. row .. ")"
                        msgTimer = 1.5
                    elseif IsTileSelectable(col, row) then
                        selectedTileCol = col
                        selectedTileRow = row
                        selectedIsLight = false
                        selectedTiles = {{ col = col, row = row, isLight = false, lightIdx = 0 }}
                        local base = GetTileType(levelData[row][col])
                        local names = { [TILE.SPAWN]="主角", [TILE.FUEL]="火焰", [TILE.GOAL]="终点",
                                        [TILE.SPIKE]="刺", [TILE.SWITCH]="开关", [TILE.GATE]="门" }
                        msgText = "选中: " .. (names[base] or "物体") .. " (" .. col .. "," .. row .. ")"
                        msgTimer = 1.5
                    else
                        ClearSelection()
                    end
                else
                    ClearSelection()
                end
            end
            return
        end

        -- 移动模式：完成拖拽
        if moveDragging then
            local col, row = ScreenToGrid(mx, my)
            col = math.max(1, math.min(MAP_COLS, col))
            row = math.max(1, math.min(MAP_ROWS, row))

            -- 只有实际移动了位置才执行
            if col ~= moveDragStartCol or row ~= moveDragStartRow then
                if multiMoving and #selectedTiles > 0 then
                    -- 多选移动：计算偏移量并移动所有选中物体
                    local offsetCol = col - moveDragStartCol
                    local offsetRow = row - moveDragStartRow

                    -- 建立已选位置集合（这些位置会被清空，所以不算被占用）
                    local selectedSet = {}
                    for _, st in ipairs(selectedTiles) do
                        selectedSet[st.row * 10000 + st.col] = true
                    end

                    -- 检查所有目标位置是否有效
                    local canMoveAll = true
                    for _, st in ipairs(selectedTiles) do
                        local nc = st.col + offsetCol
                        local nr = st.row + offsetRow
                        if nc < 1 or nc > MAP_COLS or nr < 1 or nr > MAP_ROWS then
                            canMoveAll = false
                            break
                        end
                        if not st.isLight then
                            local destVal = levelData[nr][nc]
                            if destVal ~= TILE.EMPTY and not selectedSet[nr * 10000 + nc] then
                                canMoveAll = false
                                break
                            end
                        end
                    end

                    if canMoveAll then
                        -- 先收集所有非光源的原始值
                        local tileValues = {}
                        for i, st in ipairs(selectedTiles) do
                            if not st.isLight then
                                tileValues[i] = levelData[st.row][st.col]
                            end
                        end
                        -- 清除所有非光源的原位置
                        for i, st in ipairs(selectedTiles) do
                            if not st.isLight and tileValues[i] then
                                RecordTileChange(st.col, st.row, tileValues[i], TILE.EMPTY)
                                levelData[st.row][st.col] = TILE.EMPTY
                            end
                        end
                        -- 放置到新位置
                        for i, st in ipairs(selectedTiles) do
                            local nc = st.col + offsetCol
                            local nr = st.row + offsetRow
                            if st.isLight then
                                FogOfWar.MoveLight(st.lightIdx, nc, nr)
                            else
                                levelData[nr][nc] = tileValues[i]
                                RecordTileChange(nc, nr, TILE.EMPTY, tileValues[i])
                                -- 更新 spawn 位置
                                if GetTileType(tileValues[i]) == TILE.SPAWN then
                                    spawnCol = nc
                                    spawnRow = nr
                                end
                            end
                        end
                        -- 更新 selectedTiles 坐标
                        for _, st in ipairs(selectedTiles) do
                            st.col = st.col + offsetCol
                            st.row = st.row + offsetRow
                        end
                        lightSources = FogOfWar.GetLightSources()
                        undo.dirty = true
                        undo.saveTimer = undo.saveDelay
                        msgText = #selectedTiles .. " 个物体已移动"
                        msgTimer = 1.5
                    else
                        msgText = "目标位置被占用，无法移动"
                        msgTimer = 1.5
                    end

                    moveDragging = false
                    multiMoving = false
                    return
                elseif moveDragLightIdx > 0 then
                    -- 移动光源
                    FogOfWar.MoveLight(moveDragLightIdx, col, row)
                    lightSources = FogOfWar.GetLightSources()
                    selectedTileCol = col
                    selectedTileRow = row
                    undo.dirty = true
                    undo.saveTimer = undo.saveDelay
                    msgText = "光源已移动到 (" .. col .. "," .. row .. ")"
                    msgTimer = 1.5
                else
                    -- 移动普通地块
                    local oldVal = moveDragTileValue
                    local destVal = levelData[row][col]
                    -- 目标位置为空或为同类型时才允许移动
                    if destVal == TILE.EMPTY or (row == moveDragStartRow and col == moveDragStartCol) then
                        -- 清除原位置
                        levelData[moveDragStartRow][moveDragStartCol] = TILE.EMPTY
                        -- 设置新位置
                        levelData[row][col] = oldVal
                        -- 更新 spawn 位置
                        local base = GetTileType(oldVal)
                        if base == TILE.SPAWN then
                            spawnCol = col
                            spawnRow = row
                        end
                        RecordTileChange(moveDragStartCol, moveDragStartRow, oldVal, TILE.EMPTY)
                        RecordTileChange(col, row, TILE.EMPTY, oldVal)
                        selectedTileCol = col
                        selectedTileRow = row
                        undo.dirty = true
                        undo.saveTimer = undo.saveDelay
                        local base2 = GetTileType(oldVal)
                        local names = { [TILE.SPAWN]="主角", [TILE.FUEL]="火焰", [TILE.GOAL]="终点",
                                        [TILE.SPIKE]="刺", [TILE.SWITCH]="开关", [TILE.GATE]="门" }
                        msgText = (names[base2] or "物体") .. " 移动到 (" .. col .. "," .. row .. ")"
                        msgTimer = 1.5
                    else
                        msgText = "目标位置已被占用"
                        msgTimer = 1.5
                    end
                end
            end
            moveDragging = false
            multiMoving = false
            return
        end

        if isDrawing then
            FinalizeDrawAction()
        end
        isDrawing = false
        -- 结束边界拖拽
        if boundDragActive then
            boundDragActive = false
            boundDragEdge = BOUND_EDGE_NONE
        end
    elseif button == MOUSEB_RIGHT then
        if isErasing then
            FinalizeDrawAction()
        end
        isErasing = false
    end
    lastPlacedCol = -1; lastPlacedRow = -1
end

function HandleMouseWheel(eventType, eventData)
    if editorMode == MODE_PLAY or editorMode == MODE_WORLDPLAY then return end
    if dialogMode then return end
    local wheel = eventData["Wheel"]:GetInt()

    if editorMode == MODE_WORLDMAP then
        local mx = input:GetMousePosition().x / dpr / scaleF
        local my = input:GetMousePosition().y / dpr / scaleF
        WorldMapEditor.HandleMouseWheel(wheel, mx, my)
        return
    end

    -- 侧边栏区域滚动
    local mx = input:GetMousePosition().x / dpr / scaleF
    local my = input:GetMousePosition().y / dpr / scaleF
    if sidebarOpen and mx >= screenDesignW - SIDEBAR_W then
        local maxScroll = math.max(0, #savedLevels * 22 - (screenDesignH - TOPBAR_H - BOTTOMBAR_H - 24))
        sidebarScroll = sidebarScroll - wheel * 22
        sidebarScroll = math.max(0, math.min(sidebarScroll, maxScroll))
        return
    end

    -- 缩放：以鼠标位置为中心，每次滚轮缩放 25%
    local oldZoom = zoomLevel
    if wheel > 0 then
        zoomLevel = zoomLevel * ZOOM_FACTOR
    elseif wheel < 0 then
        zoomLevel = zoomLevel / ZOOM_FACTOR
    end
    zoomLevel = math.max(ZOOM_MIN, math.min(ZOOM_MAX, zoomLevel))

    -- 以鼠标位置为中心调整相机位置，使鼠标指向的世界坐标不变
    local mapRelX = mx       -- 鼠标在地图区域的 X
    local mapRelY = my - TOPBAR_H  -- 鼠标在地图区域的 Y

    -- 鼠标指向的世界坐标（旧缩放下）
    local worldX = (mapRelX + cameraX) / oldZoom
    local worldY = (mapRelY + cameraY) / oldZoom

    -- 新缩放下，让同一世界坐标保持在鼠标位置
    cameraX = worldX * zoomLevel - mapRelX
    cameraY = worldY * zoomLevel - mapRelY
end

function HandleScreenMode(eventType, eventData)
    RecalcLayout()
end
