------------------------------------------------------------
-- gameplay/Physics.lua — 碰撞检测与地形判定
------------------------------------------------------------
local Config = require("gameplay.Config")

local M = {}

-- 外部注入的状态引用
local levelData = nil
local switchState = nil
local hiddenWallRevealed = nil

-- 地块类型（由 init 注入）
local TILE = nil

--- 注入运行时依赖
---@param deps table { levelData, switchState, hiddenWallRevealed, TILE }
function M.Inject(deps)
    levelData = deps.levelData
    switchState = deps.switchState
    hiddenWallRevealed = deps.hiddenWallRevealed
    TILE = deps.TILE
end

--- 更新运行时引用（关卡重载时调用）
function M.SetLevelData(data)
    levelData = data
end

function M.SetSwitchState(state)
    switchState = state
end

function M.SetHiddenWallRevealed(state)
    hiddenWallRevealed = state
end

--- 解码地块值：SWITCH/GATE 编码为 group*100+baseType
function M.GetTileType(value)
    if value >= 100 then
        return value % 100, math.floor(value / 100)
    end
    return value, 0
end

--- 判断某格是否为实体
function M.IsSolid(col, row)
    if col < 1 or col > Config.MAP_COLS then return true end
    if row < 1 then return false end
    if row > Config.MAP_ROWS then return false end
    local val = levelData[row][col]
    local base, group = M.GetTileType(val)
    if base == TILE.SOLID or base == TILE.SOLID_PILLAR or base == TILE.SOLID_SEWER then return true end
    if base == TILE.GATE then
        if not switchState[group] then return true end
    end
    if base == TILE.HIDDEN_WALL then
        if not hiddenWallRevealed[group] then return true end
    end
    return false
end

--- 判断某格是否为实体（仅用于光照阴影遮挡：只检查固体方块和柱子）
function M.IsSolidForLight(col, row)
    if col < 1 or col > Config.MAP_COLS then return false end
    if row < 1 or row > Config.MAP_ROWS then return false end
    local val = levelData[row][col]
    if not val or val == 0 then return false end
    local base = M.GetTileType(val)
    return base == TILE.SOLID or base == TILE.SOLID_PILLAR or base == TILE.SOLID_SEWER
end

--- 判断某格是否为平台（当前无平台类型）
function M.IsPlatform(col, row)
    if col < 1 or col > Config.MAP_COLS or row < 1 or row > Config.MAP_ROWS then return false end
    return false
end

--- 计算玩家占据的格子数
function M.PlayerGridSize()
    local totalPx = Config.PLAYER_CONFIG.pixelGridSize * Config.PLAYER_CONFIG.pixelSize
    return math.ceil(totalPx / Config.GRID)
end

--- 检测玩家在指定位置是否碰撞
function M.PlayerCollidesAt(gx, gy)
    local s = M.PlayerGridSize()
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            if M.IsSolid(gx + dx, gy + dy) then return true end
        end
    end
    return false
end

--- 检测玩家是否站在地面上
function M.PlayerOnGround(gx, gy)
    local s = M.PlayerGridSize()
    local feetRow = gy + s
    for dx = 0, s - 1 do
        if M.IsSolid(gx + dx, feetRow) or M.IsPlatform(gx + dx, feetRow) then
            return true
        end
    end
    return false
end

return M
