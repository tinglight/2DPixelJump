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

-- 试玩模式视口（16:9 比例，基于 DESIGN_W）
S.playViewW = C.DESIGN_W
S.playViewH = C.DESIGN_W * 9 / 16  -- 480 * 0.5625 = 270

-- ====================================================================
-- 来源标记（从主菜单进入 vs 从编辑器进入）
-- ====================================================================
S.fromMainMenu = false

-- 编辑器激活标记（返回主菜单时置 false，阻止所有渲染和事件处理）
S.editorActive = true

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
    cameraZoom = 2.0,
}

S.playerParamInputs = {"3", "1.0", "10", "0", "12", "2.0"}
S.playerParamFocus = 1
S.playerParamCursor = 0

-- ====================================================================
-- Gizmos 显隐（光源提示圈、光域矩形、相机框等）
-- ====================================================================
S.showGizmos = false  -- 默认隐藏，开启后显示

-- ====================================================================
-- 光源
-- ====================================================================
S.fogShowInEditor = false
S.lightSources = {}
S.selectedLightIndex = 0
S.lightDiameterInput = "6"
S.lightFeatherInput = "0.5"
S.lightGroupInput = "0"
S.lightDialogFocus = 1
S.lightDialogCursor = 0

-- ====================================================================
-- 光源区域（光域）
-- ====================================================================
S.lightZones = {}
S.selectedLightZoneIndex = 0
S.lightZoneDrawing = false       -- 是否正在拖拽框选区域
S.lightZoneStartCol = 0
S.lightZoneStartRow = 0
S.lightZoneEndCol = 0
S.lightZoneEndRow = 0

-- ====================================================================
-- 装饰物
-- ====================================================================
S.decorations = {}               -- { {col, row, typeId, brightness, scale}, ... }
S.selectedDecorationIndex = 0    -- 当前选中的装饰物索引（0=无）
S.currentDecorationType = 1      -- 当前选择的装饰物类型索引（对应 C.DECORATION_TYPES）

-- 装饰物拖拽状态
S.decoDragging = false           -- 是否正在拖拽装饰物
S.decoDragIndex = 0              -- 正在拖拽的装饰物索引
S.decoDragStartCol = 0
S.decoDragStartRow = 0

-- 装饰物弹窗状态
S.decoDialogCol = 0              -- 弹窗关联的地图位置
S.decoDialogRow = 0
S.decoDialogEditIndex = 0        -- 编辑已有装饰（0=新建）
S.decoDialogBrightness = 100     -- 明暗度 0-100
S.decoDialogScale = 100          -- 缩放比例 0-1000
S.decoDialogBrightnessInput = "100"  -- 明暗度输入框文本
S.decoDialogScaleInput = "100"       -- 缩放输入框文本
S.decoDialogFocusField = 0           -- 0=无焦点, 1=明暗度, 2=缩放
S.decoDialogCursor = 0               -- 输入框光标位置


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
-- 工具栏滑动状态
-- ====================================================================
S.toolbarScrollX = 0          -- 当前滑动偏移（设计像素，<=0 表示向右滑）
S.toolbarDragging = false     -- 正在拖拽滑动工具栏
S.toolbarDragStartX = 0       -- 拖拽起始鼠标X
S.toolbarDragStartScroll = 0  -- 拖拽起始时的 scrollX
S.toolbarDragPending = false  -- 按下但尚未确定是拖拽还是点击
S.toolbarDragPendingSlot = nil -- pending 时命中的工具槽位（nil=未命中按钮）
S.toolbarDragThreshold = 4    -- 超过此像素视为拖拽（设计坐标）

-- ====================================================================
-- 工具栏子菜单展开状态
-- ====================================================================
S.submenuOpen = false               -- 是否有子菜单展开
S.submenuGroupId = nil              -- 展开的子菜单分组 id（如 "water"）
S.submenuSlotIdx = 0                -- 触发子菜单的工具栏槽位索引（用于定位弹出位置）

-- ====================================================================
-- 工具栏编辑模式状态
-- ====================================================================
S.toolbarEditMode = false           -- 是否处于工具编辑模式
S.toolOrder = nil                   -- 自定义工具顺序（nil=默认顺序），1-based 索引数组
S.toolOrderPending = nil            -- 编辑中的临时工具顺序（未保存）
S.toolEditDragging = false          -- 编辑模式中正在拖拽工具
S.toolEditDragIndex = 0             -- 正在被拖拽的工具在 pending 数组中的索引
S.toolEditDragStartX = 0            -- 拖拽起始鼠标X
S.toolEditDragOffsetX = 0           -- 拖拽中的像素偏移

-- ====================================================================
-- 剪贴板（复制粘贴）
-- ====================================================================
S.clipboard = nil  -- { tiles = {{colOffset, rowOffset, value}}, lights = {{colOffset, rowOffset, diameter, feather}} }

-- ====================================================================
-- 难度
-- ====================================================================
S.currentDifficulty = 1

-- ====================================================================
-- 背景图
-- ====================================================================
S.backgroundImage = ""        -- 选中的背景图路径（如 "image/xxx.png"）
S.bgImageAlpha = 0.5          -- 背景图明暗度（0.0~1.0，越大越亮）
S.bgStretchToCanvas = false   -- 是否拉伸背景图为画布大小（false=铺满相机边界）
S.bgImageHandle = nil         -- NanoVG 图片句柄（运行时缓存）
S.bgDialogSelected = 0        -- 背景对话框中选中的索引
S.bgAlphaInput = "50"         -- 对话框中明暗度输入框的文本

-- ====================================================================
-- 视口缓存
-- ====================================================================
S.viewportCache = {}

-- ====================================================================
-- 顶栏按钮列表（由 Toolbar 模块填充）
-- ====================================================================
S.topBarButtons = {}

-- ====================================================================
-- 云端同步面板状态
-- ====================================================================
S.cloudPanelOpen = false       -- 面板是否展开
S.cloudBtnRect = nil           -- 按钮位置 { x, y, w, h }
S.cloudDialogMode = nil        -- "export" | "import" | nil
S.cloudExportName = ""         -- 导出自定义名称
S.cloudImportList = {}         -- 可导入文件列表

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
    inWater = false,
    inBlackWater = false,
    waterDrainAccum = 0,
    fragilePrevPlatform = nil,  -- 上一帧站立的脆弱平台连通集合
    fragileGone = {},           -- {["row_col"] = true} 已消失的脆弱格子
    fragileParticles = {},      -- 碎裂粒子列表
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
S.playCameraY = 0
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

-- 存档点状态（世界试玩期间持久，切关卡不清空）
-- checkpointFile: 最后一次存档的关卡文件名（nil=未存档，回到 spawn）
-- checkpointCol/Row: 存档点在该关卡中的格子坐标
-- checkpointActivated: 当前关卡已激活的存档点集合 {["row_col"]=true}
S.checkpointFile = nil
S.checkpointCol = nil
S.checkpointRow = nil
S.checkpointActivated = {}
S.checkpointLightPos = nil  -- 当前点燃篝火的光源位置 {col, row}

-- 死亡转场状态
S.deathTransition = {
    active = false,        -- 是否正在死亡转场
    phase = "none",        -- "circleClose" | "blackout" | "waitKey" | "none"
    timer = 0,             -- 当前 phase 内的计时
    playerScreenX = 0,     -- 死亡时玩家在屏幕上的 X 坐标（黑圈中心）
    playerScreenY = 0,     -- 死亡时玩家在屏幕上的 Y 坐标（黑圈中心）
}

-- 关卡切换过渡动画（旧版黑屏，已弃用）
S.transition = {
    active = false,
    phase = "none",
    alpha = 0,
    speed = 5.0,
    pendingFile = nil,
    pendingDir = nil,
    pendingGx = nil,
    pendingGy = nil,
}

-- 关卡切换平移过渡
S.panTransition = {
    active = false,       -- 是否正在平移过渡
    progress = 0,         -- 0~1 动画进度
    duration = 0.35,      -- 过渡时长(秒)
    direction = nil,      -- 移动方向 "left"|"right"|"up"|"down"
    -- 旧关卡快照
    oldLevelData = nil,   -- 旧关卡的 levelData 引用
    oldMapCols = 0,
    oldMapRows = 0,
    oldCamBound = nil,    -- { left, top, right, bottom }
    oldCameraX = 0,
    oldCameraY = 0,
    oldLightSources = nil,
    oldSwitchState = nil,
    oldCollected = nil,
    oldHiddenWallRevealed = nil,
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
