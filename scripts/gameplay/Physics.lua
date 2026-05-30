------------------------------------------------------------
-- gameplay/Physics.lua — 碰撞检测与地形判定
------------------------------------------------------------
local Config = require("gameplay.Config")

local M = {}

-- 外部注入的状态引用
local levelData = nil
local switchState = nil
local hiddenWallRevealed = nil
local LevelManager = nil  -- 用于获取 gameTime 和 HIDDEN_WALL_FADE_DURATION

-- 地块类型（由 init 注入）
local TILE = nil

--- 注入运行时依赖
---@param deps table { levelData, switchState, hiddenWallRevealed, TILE, LevelManager }
function M.Inject(deps)
    levelData = deps.levelData
    switchState = deps.switchState
    hiddenWallRevealed = deps.hiddenWallRevealed
    TILE = deps.TILE
    LevelManager = deps.LevelManager
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

--- 判断某格是否为斜坡类型
function M.IsSlope(tileBase)
    return tileBase >= 19 and tileBase <= 22
end

--- 获取斜坡在指定子格位置是否为实体
--- subCol, subRow: 1~4 的子格坐标（4x4细分）
---@param tileBase number 斜坡类型
---@param subCol number 子格列 1~4
---@param subRow number 子格行 1~4
---@return boolean
function M.IsSlopeSolidAt(tileBase, subCol, subRow)
    if tileBase == 19 then       -- SLOPE_TR: 左下直角
        return subCol >= (5 - subRow)
    elseif tileBase == 20 then   -- SLOPE_TL: 右下直角
        return subCol <= subRow
    elseif tileBase == 21 then   -- SLOPE_BR: 左上直角
        return subCol >= subRow
    elseif tileBase == 22 then   -- SLOPE_BL: 右上直角
        return subCol <= (5 - subRow)
    end
    return false
end

--- 判断某格是否为实体
function M.IsSolid(col, row)
    if col < 1 or col > Config.MAP_COLS then return true end
    if row < 1 then return false end
    if row > Config.MAP_ROWS then return false end
    local val = levelData[row][col]
    local base, group = M.GetTileType(val)
    if base == TILE.SOLID or base == TILE.SOLID_PILLAR or base == TILE.SOLID_SEWER then return true end
    -- 斜坡视为实体（完整格子碰撞）
    if M.IsSlope(base) then return true end
    if base == TILE.GATE then
        if not switchState[group] then return true end
    end
    if base == TILE.HIDDEN_WALL then
        local revealTime = hiddenWallRevealed[group]
        if not revealTime then
            return true  -- 未揭示，完全实体
        end
        -- 揭示后等待渐变完成才取消碰撞
        local fadeDuration = LevelManager and LevelManager.HIDDEN_WALL_FADE_DURATION or 0.2
        local gameTime = LevelManager and LevelManager.gameTime or 0
        if gameTime - revealTime < fadeDuration then
            return true  -- 渐变中仍然保持碰撞
        end
    end
    return false
end

--- 判断某格是否为实体（仅用于光照阴影遮挡：检查固体方块、柱子、斜坡和未消失的隐藏墙）
function M.IsSolidForLight(col, row)
    if col < 1 or col > Config.MAP_COLS then return false end
    if row < 1 or row > Config.MAP_ROWS then return false end
    local val = levelData[row][col]
    if not val or val == 0 then return false end
    local base, group = M.GetTileType(val)
    if base == TILE.SOLID or base == TILE.SOLID_PILLAR or base == TILE.SOLID_SEWER then
        return true
    end
    -- 斜坡阻挡光线
    if M.IsSlope(base) then return true end
    -- 隐藏墙：未揭示或正在渐变中都阻挡光线
    if base == TILE.HIDDEN_WALL then
        local revealTime = hiddenWallRevealed[group]
        if not revealTime then
            return true  -- 未揭示，阻挡光线
        end
        local fadeDuration = LevelManager and LevelManager.HIDDEN_WALL_FADE_DURATION or 0.2
        local gameTime = LevelManager and LevelManager.gameTime or 0
        if gameTime - revealTime < fadeDuration then
            return true  -- 渐变中仍阻挡光线
        end
    end
    return false
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

--- 检测玩家在指定位置是否碰撞（忽略斜坡）
--- 用于斜坡行走逻辑：先忽略斜坡碰撞，再单独判断斜坡通行
function M.PlayerCollidesAtIgnoreSlopes(gx, gy)
    local s = M.PlayerGridSize()
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            if M.IsSolidNonSlope(gx + dx, gy + dy) then return true end
        end
    end
    return false
end

--- 判断某格是否为实体（不含斜坡）
function M.IsSolidNonSlope(col, row)
    if col < 1 or col > Config.MAP_COLS then return true end
    if row < 1 then return false end
    if row > Config.MAP_ROWS then return false end
    local val = levelData[row][col]
    local base, group = M.GetTileType(val)
    if base == TILE.SOLID or base == TILE.SOLID_PILLAR or base == TILE.SOLID_SEWER then return true end
    -- 斜坡不包含在内
    if base == TILE.GATE then
        if not switchState[group] then return true end
    end
    if base == TILE.HIDDEN_WALL then
        local revealTime = hiddenWallRevealed[group]
        if not revealTime then
            return true
        end
        local fadeDuration = LevelManager and LevelManager.HIDDEN_WALL_FADE_DURATION or 0.2
        local gameTime = LevelManager and LevelManager.gameTime or 0
        if gameTime - revealTime < fadeDuration then
            return true
        end
    end
    return false
end

--- 获取指定格子的斜坡类型（如果是斜坡返回 base，否则返回 nil）
function M.GetSlopeAt(col, row)
    if col < 1 or col > Config.MAP_COLS or row < 1 or row > Config.MAP_ROWS then return nil end
    local val = levelData[row][col]
    local base = M.GetTileType(val)
    if M.IsSlope(base) then return base end
    return nil
end

--- 检测玩家脚下（2格宽的底部行）是否有斜坡，返回斜坡类型或 nil
function M.GetSlopeUnderPlayer(gx, gy)
    local s = M.PlayerGridSize()
    local feetRow = gy + s - 1  -- 玩家最底行
    for dx = 0, s - 1 do
        local slope = M.GetSlopeAt(gx + dx, feetRow)
        if slope then return slope end
    end
    -- 也检查脚下一格（站在斜坡顶上）
    local belowRow = gy + s
    for dx = 0, s - 1 do
        local slope = M.GetSlopeAt(gx + dx, belowRow)
        if slope then return slope end
    end
    return nil
end

--- 检测玩家目标位置是否有斜坡挡住，返回斜坡类型或 nil
--- 检查玩家占据的所有格子
function M.GetSlopeInPlayerArea(gx, gy)
    local s = M.PlayerGridSize()
    for dy = 0, s - 1 do
        for dx = 0, s - 1 do
            local slope = M.GetSlopeAt(gx + dx, gy + dy)
            if slope then return slope end
        end
    end
    return nil
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
