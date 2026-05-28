-- ====================================================================
-- editor/State.lua - 编辑器共享可变状态
-- ====================================================================
-- 所有跨模块共享的可变状态集中在此，避免循环依赖和全局变量泄漏。
-- 各模块通过 require 获取此表的引用，直接读写字段。

local C = require "editor.Constants"

---@class EditorState
local S = {}

-- ====================================================================
-- NanoVG 上下文（由主入口初始化）
-- ====================================================================
S.vg = nil

-- ====================================================================
-- 屏幕/分辨率状态
-- ====================================================================
S.physW = 0
S.physH = 0
S.dpr = 1.0
S.logicalW = 0
S.logicalH = 0
S.scaleF = 1.0
S.screenDesignW = C.DESIGN_W
S.screenDesignH = C.DESIGN_H

-- ====================================================================
-- 编辑器核心状态
-- ====================================================================
S.editorMode = C.MODE_EDIT
S.levelData = {}
S.currentTool = 1
S.currentGroup = 1
S.cameraX = 0
S.cameraY = 0
S.zoomLevel = 1.0
S.editorClock = 0

-- ====================================================================
-- 地图尺寸（可动态变化）
-- ====================================================================
S.MAP_COLS = C.DEFAULT_MAP_COLS
S.MAP_ROWS = C.DEFAULT_MAP_ROWS

-- ====================================================================
-- 出生点
-- ====================================================================
S.spawnCol = 3
S.spawnRow = C.DEFAULT_MAP_ROWS - 3

-- ====================================================================
-- 消息提示
-- ====================================================================
S.msgText = ""
S.msgTimer = 0

-- ====================================================================
-- 当前关卡文件名与显示名称
-- ====================================================================
S.currentLevelName = ""
S.currentLevelDisplayName = ""

-- ====================================================================
-- 隐藏墙分组系统
-- ====================================================================
S.hiddenWall = {
    group = 1,
    lastEditTime = 0,
    timeout = C.HIDDEN_WALL_TIMEOUT,
    prevTool = 0,
    baseColor = { 80, 200, 220 },
}

-- ====================================================================
-- 绘制状态
-- ====================================================================
S.isDrawing = false
S.isErasing = false
S.lastPlacedCol = -1
S.lastPlacedRow = -1

-- ====================================================================
-- 摄像机边界
-- ====================================================================
S.camBound = {
    left = 1,
    top = 1,
    right = C.DEFAULT_MAP_COLS,
    bottom = C.DEFAULT_MAP_ROWS,
}

-- ====================================================================
-- 边界拖拽
-- ====================================================================
S.boundDragEdge = C.BOUND_EDGE_NONE
S.boundDragActive = false

-- ====================================================================
-- 侧边栏
-- ====================================================================
S.sidebarOpen = true
S.savedLevels = {}
S.sidebarScroll = 0
S.sidebarLastClickFile = nil
S.sidebarLastClickTime = 0

-- ====================================================================
-- 对话框
-- ====================================================================
S.dialogMode = nil
S.dialogTarget = nil
S.renameInput = ""
S.renameCursor = 0
S.renameBlink = 0

-- ====================================================================
-- IME 组合输入状态
-- ====================================================================
S.imeComposition = ""    -- 当前 IME 组合文本（拼音等）
S.imeCursor = 0          -- 组合文本中的光标位置

-- ====================================================================
-- 画布对话框
-- ====================================================================
S.canvasWidthInput = ""
S.canvasHeightInput = ""
S.canvasFocusField = 1
S.canvasCursor = 0

-- ====================================================================
-- 玩家参数
-- ====================================================================
S.playerParams = {
    baseJumpGrids = 3,
    fallJumpMultiplier = 1.0,
    maxFallGrids = 10,
    maxJumpGrids = 0,
    defaultLightDiameter = 12,
    cameraZoom = 1.0,
}

S.playerParamInputs = {"3", "1.0", "10", "0", "12", "1.0"}
S.playerParamFocus = 1
S.playerParamCursor = 0

-- ====================================================================
-- 光源
-- ====================================================================
S.fogShowInEditor = false
S.lightSources = {}
S.selectedLightIndex = 0
S.lightDiameterInput = "6"
S.lightFeatherInput = "0.5"
S.lightDialogFocus = 1
S.lightDialogCursor = 0

-- ====================================================================
-- 交互模式 & 选取
-- ====================================================================
S.interactMode = C.INTERACT_DRAW
S.selectedTileCol = 0
S.selectedTileRow = 0
S.selectedIsLight = false
S.selectedTiles = {}

-- ====================================================================
-- 移动拖拽
-- ====================================================================
S.moveDragging = false
S.moveDragStartCol = 0
S.moveDragStartRow = 0
S.moveDragCurrentCol = 0
S.moveDragCurrentRow = 0
S.moveDragTileValue = 0
S.moveDragLightIdx = 0
S.multiMoving = false

-- ====================================================================
-- 中键拖拽视窗
-- ====================================================================
S.midDragging = false
S.midDragLastX = 0
S.midDragLastY = 0

-- ====================================================================
-- 框选
-- ====================================================================
S.boxSelectActive = false
S.boxSelectStartX = 0
S.boxSelectStartY = 0
S.boxSelectCurrentX = 0
S.boxSelectCurrentY = 0

-- ====================================================================
-- 难度
-- ====================================================================
S.currentDifficulty = 1

-- ====================================================================
-- 视口缓存
-- ====================================================================
S.viewportCache = {}

-- ====================================================================
-- 顶栏按钮列表（由 Toolbar 模块填充）
-- ====================================================================
S.topBarButtons = {}

-- ====================================================================
-- 试玩模式状态
-- ====================================================================
S.play = {
    gridX = 3, gridY = 10,
    isOnGround = false,
    isJumping = false,
    jumpGridsRemain = 0,
    facingRight = true,
    moveTimer = 0,
    fallTimer = 0,
    fallTickCurrent = C.PLAY_FALL_BASE,
    jumpTimer = 0,
    fallGridCount = 0,
    alive = true,
    won = false,
    deathTimer = 0,
    isMoving = false,
    moveAnimTime = 0,
    fallAnimTime = 0,
    switchState = {},
    collected = {},
    hiddenWallRevealed = {},
}

-- 像素状态
S.pixelState = {}
S.playTotalPixels = 0
S.playAlivePixels = 0
S.stripOrder = {}

-- 火焰动画
S.flameAnimTimer = 0
S.flameAnimFrame = 0
S.flameTime = 0
S.rowOffsets = {}
S.rowVOffsets = {}
S.tipPixels = {}
S.tipSpawnTimer = 0
S.playFallParticles = {}

-- 试玩相机/时间
S.prevPlayLeft = false
S.prevPlayRight = false
S.playMoveFirst = false
S.playCameraX = 0
S.playGameTime = 0

-- 世界试玩
S.worldPlayData = nil
S.worldPlayCurrentFile = nil
S.worldPlayCooldown = 0

-- 飞行道具（当前关卡内飞行中的道具列表）
S.projectiles = {}

-- 跨关卡开关状态（世界试玩期间持久，切关卡不清空）
-- 格式: { ["level_2.json"] = { [1] = true, [3] = true } }
S.crossSwitchState = {}

-- 关卡切换过渡动画
S.transition = {
    active = false,       -- 是否正在过渡
    phase = "none",       -- "fadeOut" | "fadeIn" | "none"
    alpha = 0,            -- 当前遮罩透明度 0~1
    speed = 5.0,          -- 淡入淡出速度（每秒 alpha 变化量）
    pendingFile = nil,    -- 待加载的目标关卡文件名
    pendingDir = nil,     -- 来源方向
    pendingGx = nil,      -- 切换前的 gridX
    pendingGy = nil,      -- 切换前的 gridY
}

-- ====================================================================
-- 便捷方法
-- ====================================================================

function S.SetMessage(text, duration)
    S.msgText = text
    S.msgTimer = duration or 2.0
end

function S.ClearSelection()
    S.selectedTileCol = 0
    S.selectedTileRow = 0
    S.selectedIsLight = false
    S.selectedTiles = {}
    S.boxSelectActive = false
end

return S
