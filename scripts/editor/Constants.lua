-- ====================================================================
-- editor/Constants.lua - 所有常量、枚举、配置定义
-- ====================================================================

local M = {}

-- ====================================================================
-- 版本号
-- ====================================================================
M.VERSION = require "version"

-- ====================================================================
-- 网格与设计尺寸
-- ====================================================================
M.GRID = 16
M.DESIGN_W = 480
M.DESIGN_H = 272

-- ====================================================================
-- 默认地图尺寸
-- ====================================================================
M.DEFAULT_MAP_COLS = 40
M.DEFAULT_MAP_ROWS = 20

-- ====================================================================
-- UI 布局常量
-- ====================================================================
M.TOPBAR_H = 22
M.BOTTOMBAR_H = 56
M.SIDEBAR_W = 100
M.AUTO_SAVE_DELAY = 1.0

-- ====================================================================
-- 地块类型枚举
-- ====================================================================
M.TILE = {
    EMPTY        = 0,
    SOLID        = 1,
    SPAWN        = 2,
    FUEL         = 3,
    GOAL         = 4,
    SPIKE        = 5,
    SWITCH       = 6,
    GATE         = 7,
    HIDDEN_WALL  = 8,
    WATER        = 9,
    POISON_WATER = 10,
    BLACK_WATER  = 11,
    LADDER       = 12,
    SOLID_PILLAR = 13,
    CHECKPOINT   = 14,
    PIPE         = 15,
    FRAGILE      = 16,
}

-- ====================================================================
-- 编辑器模式枚举
-- ====================================================================
M.MODE_EDIT      = 1
M.MODE_PLAY      = 2
M.MODE_WORLDMAP  = 3
M.MODE_WORLDPLAY = 4
M.MODE = { EDIT = 1, PLAY = 2, WORLDMAP = 3, WORLDPLAY = 4 }

-- ====================================================================
-- 交互模式枚举
-- ====================================================================
M.INTERACT_DRAW   = 1
M.INTERACT_SELECT = 2
M.INTERACT_MOVE   = 3
M.INTERACT = { DRAW = 1, SELECT = 2, MOVE = 3 }

-- ====================================================================
-- 边界拖拽边枚举
-- ====================================================================
M.BOUND_EDGE_NONE   = 0
M.BOUND_EDGE_LEFT   = 1
M.BOUND_EDGE_RIGHT  = 2
M.BOUND_EDGE_TOP    = 3
M.BOUND_EDGE_BOTTOM = 4
M.BOUND_EDGE = { NONE = 0, LEFT = 1, RIGHT = 2, TOP = 3, BOTTOM = 4 }

-- ====================================================================
-- 缩放常量
-- ====================================================================
M.ZOOM_MIN    = 0.25
M.ZOOM_MAX    = 4.0
M.ZOOM_FACTOR = 1.25

-- ====================================================================
-- 摄像机边界默认值
-- ====================================================================
M.CAM_BOUND_DEFAULT   = 20
M.BOUND_DRAG_THRESHOLD = 6

-- ====================================================================
-- 颜色组系统
-- ====================================================================
M.MAX_GROUPS = 4

M.GROUP_COLORS = {
    [1] = { 220, 60, 60 },
    [2] = { 60, 120, 220 },
    [3] = { 60, 200, 60 },
    [4] = { 220, 180, 40 },
}

M.GROUP_NAMES = { "红", "蓝", "绿", "黄" }

-- ====================================================================
-- 工具分组定义
-- ====================================================================
M.TOOL_GROUPS = {
    { id = "terrain", name = "地形", color = {80, 130, 180} },
    { id = "player",  name = "角色", color = {255, 200, 50} },
    { id = "trap",    name = "陷阱", color = {220, 60, 60} },
    { id = "puzzle",  name = "机关", color = {130, 80, 220} },
    { id = "pickup",  name = "补给", color = {60, 200, 100} },
}

-- ====================================================================
-- 工具列表
-- ====================================================================
M.TOOLS = {
    { id = "SOLID",       tile = M.TILE.SOLID,       name = "砖块", color = {80, 90, 100, 255},   group = "terrain",
        submenu = "collision" },
    { id = "SOLID_PILLAR", tile = M.TILE.SOLID_PILLAR, name = "柱子", color = {90, 80, 110, 255}, group = "terrain",
        submenu = "collision" },
    { id = "SPAWN",       tile = M.TILE.SPAWN,       name = "主角", color = {255, 200, 50, 255},  group = "player" },
    { id = "FUEL",        tile = M.TILE.FUEL,        name = "火焰", color = {255, 100, 20, 255},  group = "pickup" },
    { id = "GOAL",        tile = M.TILE.GOAL,        name = "终点", color = {100, 255, 100, 255}, group = "pickup" },
    { id = "SPIKE",       tile = M.TILE.SPIKE,       name = "刺",   color = {255, 50, 50, 255},   group = "trap" },
    { id = "WATER",       tile = M.TILE.WATER,       name = "水",   color = {60, 140, 255, 255},  group = "trap",
        submenu = "water" },
    { id = "POISON_WATER", tile = M.TILE.POISON_WATER, name = "毒水", color = {50, 220, 80, 255}, group = "trap",
        submenu = "water" },
    { id = "BLACK_WATER", tile = M.TILE.BLACK_WATER, name = "黑水", color = {100, 100, 110, 255}, group = "trap",
        submenu = "water" },
    { id = "PIPE", tile = M.TILE.PIPE, name = "水管", color = {62, 67, 78, 255}, group = "trap",
        submenu = "water" },
    { id = "SWITCH",      tile = M.TILE.SWITCH,      name = "开关", color = {200, 200, 50, 255},  group = "puzzle" },
    { id = "GATE",        tile = M.TILE.GATE,        name = "门",   color = {150, 100, 200, 255}, group = "puzzle" },
    { id = "HIDDEN_WALL", tile = M.TILE.HIDDEN_WALL, name = "隐墙", color = {100, 180, 200, 255}, group = "puzzle" },
    { id = "LADDER",      tile = M.TILE.LADDER,      name = "梯子", color = {160, 110, 50, 255},  group = "terrain" },
    { id = "CHECKPOINT",  tile = M.TILE.CHECKPOINT,   name = "篝火", color = {255, 140, 30, 255},  group = "pickup" },
    { id = "FRAGILE",     tile = M.TILE.FRAGILE,     name = "脆台", color = {180, 150, 100, 255}, group = "terrain" },
    { id = "LIGHT",       tile = -1,                 name = "光源", color = {255, 220, 80, 255},  group = "terrain" },
    { id = "LIGHT_ZONE", tile = -2,                 name = "光域", color = {255, 160, 40, 255},  group = "terrain" },
}

M.LIGHT_TOOL_INDEX = 17
M.LIGHT_ZONE_TOOL_INDEX = 18
M.HIDDEN_WALL_TOOL_INDEX = 13

-- ====================================================================
-- 子菜单分组定义
-- ====================================================================
-- 每个子菜单组的首选工具索引（展示在工具栏上的"代表"）
M.SUBMENU_GROUPS = {
    water = {
        label = "水",
        tools = {},  -- 在初始化时自动填充
    },
    collision = {
        label = "碰撞",
        tools = {},  -- 在初始化时自动填充
    },
}

-- 初始化子菜单工具索引
for i, tool in ipairs(M.TOOLS) do
    if tool.submenu and M.SUBMENU_GROUPS[tool.submenu] then
        table.insert(M.SUBMENU_GROUPS[tool.submenu].tools, i)
    end
end

-- ====================================================================
-- 水方块物理常量
-- ====================================================================
M.WATER_ENERGY_DRAIN_PER_SEC = 10    -- 普通水：每秒消耗能量（像素数）
M.BLACK_WATER_SPEED_MULT = 2.5       -- 黑水：移动tick乘数（越大越慢）

-- ====================================================================
-- 管道系统常量
-- ====================================================================
M.PIPE_WIDTH  = 5              -- 管道宽度(格)
M.PIPE_HEIGHT = 5              -- 管道高度(格)
M.PIPE_EMIT_RATE    = 55       -- 粒子发射速率(个/秒)
M.PIPE_PARTICLE_MAX = 120      -- 最大粒子数
M.PIPE_GRAVITY      = 280      -- 粒子重力加速度(px/s²)
M.PIPE_INITIAL_VY   = 70       -- 粒子初始下落速度(px/s)
M.PIPE_SPLASH_COUNT = 3        -- 着水溅射粒子数
M.PIPE_SPREAD_X     = 30       -- 水平扩散范围(px)
M.PIPE_STREAM_WIDTH = 40       -- 水柱宽度(px)

-- 管道水类型索引映射
M.PIPE_WATER_TYPES = {
    [1] = M.TILE.WATER,
    [2] = M.TILE.POISON_WATER,
    [3] = M.TILE.BLACK_WATER,
}

-- 管道水颜色表
M.PIPE_WATER_COLORS = {
    [M.TILE.WATER]        = { 60, 140, 255 },
    [M.TILE.POISON_WATER] = { 50, 220, 80 },
    [M.TILE.BLACK_WATER]  = { 100, 100, 110 },
}

-- ====================================================================
-- 难度系统
-- ====================================================================
M.DIFFICULTIES = { "easy", "normal", "hard" }
M.DIFFICULTY_NAMES = { easy = "简单", normal = "普通", hard = "困难" }

-- ====================================================================
-- 试玩模式物理常量
-- ====================================================================
M.PLAY_MOVE_TICK  = 0.10
M.PLAY_FALL_BASE  = 0.12
M.PLAY_FALL_MIN   = 0.04
M.PLAY_FALL_ACCEL = 0.015
M.PLAY_JUMP_TICK  = 0.07
M.PLAY_BASE_JUMP  = 3
M.PLAY_RECOVER_PER_SEC = 6
M.PLAY_CLIMB_TICK = 0.09      -- 梯子攀爬每格间隔（秒）

-- ====================================================================
-- 火焰渲染配置
-- ====================================================================
M.FLAME_CFG = {
    pixelGridSize = 10,
    pixelSize = 3,
    flickerSpeed = 8.0,
}

M.FLAME_ANIM_FPS = 10

-- 火焰形状（10x10 点阵）
M.CHAR_SHAPE = {
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

-- 火焰渐变色
M.FLAME_COLORS = {
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

-- 角色格子高度
M.PLAYER_GRID_H = math.ceil(
    M.FLAME_CFG.pixelGridSize * M.FLAME_CFG.pixelSize / M.GRID
)

-- ====================================================================
-- 玩家参数标签/键名
-- ====================================================================
M.PLAYER_PARAM_LABELS = {
    "满血跳跃(格)", "下落倍率", "最大下落(格)", "最大跳跃(格)", "主角光源(格)", "相机大小"
}
M.PLAYER_PARAM_KEYS = {
    "baseJumpGrids", "fallJumpMultiplier", "maxFallGrids", "maxJumpGrids", "defaultLightDiameter", "cameraZoom"
}

-- ====================================================================
-- 框选阈值
-- ====================================================================
M.BOX_SELECT_THRESHOLD = 4

-- ====================================================================
-- 隐藏墙超时
-- ====================================================================
M.HIDDEN_WALL_TIMEOUT = 5.0

-- ====================================================================
-- 飞行道具常量
-- ====================================================================
M.PROJECTILE_SPEED = 180       -- 水平速度 px/s (≈11格/s)
M.PROJECTILE_GRAVITY = 30     -- 轻微重力 px/s²
M.PROJECTILE_LIFE = 4.0       -- 最大存活时间(s)
M.PROJECTILE_SIZE = 5         -- 渲染半径(px)

-- ====================================================================
-- 工具辅助函数
-- ====================================================================

---@param tool table
---@return number[]
function M.GetToolGroupColor(tool)
    for _, g in ipairs(M.TOOL_GROUPS) do
        if g.id == tool.group then return g.color end
    end
    return {100, 100, 100}
end

return M
