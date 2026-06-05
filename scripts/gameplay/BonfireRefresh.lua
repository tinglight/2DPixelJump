------------------------------------------------------------
-- gameplay/BonfireRefresh.lua — 机关复位系统
-- 统一管理"篝火点燃"和"玩家重生"时的机关复位逻辑。
-- 设计为开放注册模式，后续新增需要复位的机关只需调用 Register。
--
-- 复位时机：
--   1. 玩家点燃（或重新点燃）篝火 → OnBonfireLit()
--   2. 玩家死亡重生 → OnRespawn()
-- 两者执行相同的复位逻辑：遍历所有已注册 handler 的 refresh()。
------------------------------------------------------------
local Config = require("gameplay.Config")
local FogOfWar = require("rendering.FogOfWar")

local M = {}

-- 依赖（通过 Inject 注入）
local LevelManager = nil
local Physics = nil

function M.Inject(deps)
    LevelManager = deps.LevelManager
    Physics = deps.Physics
end

-- ====================================================================
-- 注册表：每个条目描述一种可被复位的机关
-- ====================================================================
---@class RefreshHandler
---@field name string 机关名称（用于日志）
---@field refresh fun() 执行复位的回调函数

---@type RefreshHandler[]
local handlers = {}

--- 注册一种可复位的机关
---@param handler RefreshHandler
function M.Register(handler)
    table.insert(handlers, handler)
    print("[BonfireRefresh] Registered: " .. handler.name)
end

--- 注销指定名称的机关（如有需要）
---@param name string
function M.Unregister(name)
    for i = #handlers, 1, -1 do
        if handlers[i].name == name then
            table.remove(handlers, i)
            print("[BonfireRefresh] Unregistered: " .. name)
            return
        end
    end
end

-- ====================================================================
-- 核心复位入口（篝火点燃 / 玩家重生 共用）
-- ====================================================================

--- 执行所有已注册 handler 的复位逻辑
---@param reason string 触发原因（用于日志）
local function ExecuteRefresh(reason)
    print("[BonfireRefresh] " .. reason .. "! Refreshing " .. #handlers .. " handler(s)...")
    for _, handler in ipairs(handlers) do
        local ok, err = pcall(handler.refresh)
        if not ok then
            print("[BonfireRefresh] ERROR in '" .. handler.name .. "': " .. tostring(err))
        end
    end
end

--- 篝火点燃/重新点燃时调用
function M.OnBonfireLit()
    ExecuteRefresh("Bonfire lit")
end

--- 玩家死亡重生时调用（与篝火点燃执行相同的复位逻辑）
function M.OnRespawn()
    ExecuteRefresh("Player respawn")
end

-- ====================================================================
-- FUEL 原始位置缓存
-- key = "row_col", value = 原始 tile 值
-- ====================================================================
M._fuelOriginalTiles = {}

-- ====================================================================
-- 关卡加载后扫描并缓存 FUEL 位置
-- ====================================================================

--- 扫描当前关卡的所有 FUEL 位置，缓存原始 tile 值。
--- 必须在关卡加载完成后（levelData 已填充）调用。
function M.ScanFuelPositions()
    M._fuelOriginalTiles = {}
    if not LevelManager or not Physics then
        print("[BonfireRefresh] ScanFuelPositions: missing deps!")
        return
    end
    local TILE = LevelManager.TILE
    if not TILE then
        print("[BonfireRefresh] ScanFuelPositions: TILE is nil!")
        return
    end

    local count = 0
    for row = 1, Config.MAP_ROWS do
        local rowData = LevelManager.levelData[row]
        if rowData then
            for col = 1, Config.MAP_COLS do
                local val = rowData[col]
                if val and val ~= 0 then
                    local base = Physics.GetTileType(val)
                    if base == TILE.FUEL then
                        local key = row .. "_" .. col
                        M._fuelOriginalTiles[key] = val
                        count = count + 1
                    end
                end
            end
        end
    end
    print("[BonfireRefresh] Scanned " .. count .. " FUEL position(s) in level")
end

-- ====================================================================
-- 内置刷新器：火焰燃料 (FUEL)
-- ====================================================================

--- 刷新所有已拾取的 FUEL 机关：
--- 1. 恢复 levelData 中的 tile 值（从 EMPTY 恢复为 FUEL）
--- 2. 清除 collectedItems 中对应条目（使玩家可以重新拾取）
function M.RefreshFuel()
    if not LevelManager then
        print("[BonfireRefresh] RefreshFuel: LevelManager is nil!")
        return
    end

    local totalCached = 0
    for _ in pairs(M._fuelOriginalTiles) do totalCached = totalCached + 1 end

    local restored = 0

    for key, originalVal in pairs(M._fuelOriginalTiles) do
        local row, col = key:match("^(%d+)_(%d+)$")
        if row and col then
            row = tonumber(row)
            col = tonumber(col)
            local rowData = LevelManager.levelData[row]
            if rowData then
                local currentVal = rowData[col]
                if currentVal ~= originalVal then
                    rowData[col] = originalVal
                    restored = restored + 1
                end
                LevelManager.collectedItems[key] = nil
            end
        end
    end

    LevelManager.fuelCount = 0

    print("[BonfireRefresh] RefreshFuel: cached=" .. totalCached
        .. ", restored=" .. restored .. " FUEL tile(s)")
end

-- ====================================================================
-- 内置刷新器：灯光 (Lights) — 将被火球点亮的灯恢复为熄灭
-- ====================================================================

function M.RefreshLights()
    local count = FogOfWar.ResetIgnitedLights()
    print("[BonfireRefresh] RefreshLights: extinguished " .. count .. " light(s)")
end

-- ====================================================================
-- 内置刷新器：开关/门 (Switch/Gate) — 重置开关和门状态
-- ====================================================================

function M.RefreshSwitches()
    if not LevelManager then
        print("[BonfireRefresh] RefreshSwitches: LevelManager is nil!")
        return
    end

    local switchCount = 0
    for _ in pairs(LevelManager.switchState) do switchCount = switchCount + 1 end

    LevelManager.switchState = {}
    LevelManager.switchCollected = {}

    -- 同步到 Physics 模块
    if Physics and Physics.SetSwitchState then
        Physics.SetSwitchState(LevelManager.switchState)
    end

    print("[BonfireRefresh] RefreshSwitches: reset " .. switchCount .. " switch group(s)")
end

return M
