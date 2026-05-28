-- ====================================================================
-- editor/Persistence.lua - 保存/加载/重命名/删除（副作用模块）
-- ====================================================================

local C = require "editor.Constants"
local S = require "editor.State"
local Undo = require "editor.UndoSystem"
local FogOfWar = require "FogOfWar"
local CloudStorage = require "CloudStorage"
local WorldMapEditor = require "WorldMapEditor"

local TILE = C.TILE
local M = {}

-- ====================================================================
-- 关卡列表管理
-- ====================================================================

--- 从关卡文件读取自定义显示名称
---@param fname string
---@param defaultName string
---@return string
function M.ReadLevelDisplayName(fname, defaultName)
    local json = CloudStorage.Load(fname)
    if not json then return defaultName end
    local ok, data = pcall(cjson.decode, json)
    if ok and data and data.levelName and data.levelName ~= "" then
        return data.levelName
    end
    return defaultName
end

--- 刷新已保存关卡列表
function M.RefreshSavedLevels()
    S.savedLevels = {}
    local files = CloudStorage.ListLevels()
    for _, fname in ipairs(files) do
        local idx = tonumber(fname:match("level_(%d+)%.json")) or 0
        local defaultName = idx > 0 and ("关卡 " .. idx) or "关卡 (旧)"
        local displayName = M.ReadLevelDisplayName(fname, defaultName)
        table.insert(S.savedLevels, {
            name = displayName, file = fname, index = idx,
        })
    end
end

-- ====================================================================
-- 保存
-- ====================================================================

--- 序列化当前关卡数据为 table
---@return table
function M.SerializeLevel()
    local data = {
        cols = S.MAP_COLS,
        rows = S.MAP_ROWS,
        spawn = { col = S.spawnCol, row = S.spawnRow },
        tiles = {},
        camBound = {
            left = S.camBound.left,
            top = S.camBound.top,
            right = S.camBound.right,
            bottom = S.camBound.bottom,
        },
        playerParams = {
            baseJumpGrids = S.playerParams.baseJumpGrids,
            fallJumpMultiplier = S.playerParams.fallJumpMultiplier,
            maxFallGrids = S.playerParams.maxFallGrids,
            maxJumpGrids = S.playerParams.maxJumpGrids,
            defaultLightDiameter = S.playerParams.defaultLightDiameter,
            cameraZoom = S.playerParams.cameraZoom,
        },
        lightSources = FogOfWar.Serialize(),
    }
    -- 保留关卡显示名称（确保云端保存后不丢失）
    if S.currentLevelDisplayName ~= "" then
        data.levelName = S.currentLevelDisplayName
    end
    for row = 1, S.MAP_ROWS do
        for col = 1, S.MAP_COLS do
            local v = S.levelData[row][col]
            if v ~= TILE.EMPTY and v ~= TILE.SPAWN then
                table.insert(data.tiles, { col = col, row = row, v = v })
            end
        end
    end
    return data
end

--- 保存当前关卡到云存储
function M.SaveLevel()
    local data = M.SerializeLevel()
    local json = cjson.encode(data)

    local fname
    if S.currentLevelName ~= "" then
        fname = S.currentLevelName
    else
        local idx = CloudStorage.GetNextIndex()
        fname = "level_" .. idx .. ".json"
        S.currentLevelName = fname
    end

    CloudStorage.Save(fname, json, function(ok, err)
        if ok then
            local tileCount = #data.tiles
            S.SetMessage("已保存: " .. fname .. " (" .. tileCount .. " 块)", 2.0)
            M.RefreshSavedLevels()
        else
            S.SetMessage("保存失败: " .. (err or "未知错误"), 3.0)
        end
    end)
end

--- 自动保存（延迟触发）
function M.TryAutoSave()
    if Undo.dirty and S.currentLevelName ~= "" then
        M.SaveLevel()
        Undo.dirty = false
    end
end

--- 切换前自动保存
function M.AutoSaveBeforeSwitch()
    if S.currentLevelName ~= "" then
        S.viewportCache[S.currentLevelName] = {
            cameraX = S.cameraX,
            cameraY = S.cameraY,
            zoomLevel = S.zoomLevel,
        }
    end
    if Undo.dirty and S.currentLevelName ~= "" then
        M.SaveLevel()
        Undo.dirty = false
    end
    Undo.Reset()
end

--- 保存为新关卡
function M.SaveAsNewLevel()
    S.currentLevelName = ""
    M.SaveLevel()
end

-- ====================================================================
-- 加载
-- ====================================================================

--- 加载关卡数据到编辑器状态
---@param filename string
function M.LoadLevel(filename)
    local fname = filename or "level.json"
    local json = CloudStorage.Load(fname)
    if not json then
        S.SetMessage("未找到: " .. fname, 3.0)
        return
    end
    local ok, data = pcall(cjson.decode, json)
    if not ok or not data then
        S.SetMessage("解析失败!", 3.0)
        return
    end

    M.ApplyLevelData(data)
    S.currentLevelName = fname
    M.RestoreViewport(fname)
    Undo.Reset()
    S.SetMessage("已加载: " .. fname, 2.0)
end

--- 将解码后的关卡数据应用到编辑器状态
---@param data table
function M.ApplyLevelData(data)
    if data.cols and data.cols >= 10 then S.MAP_COLS = data.cols end
    if data.rows and data.rows >= 5 then S.MAP_ROWS = data.rows end

    -- 加载关卡显示名称
    S.currentLevelDisplayName = (data.levelName and data.levelName ~= "") and data.levelName or ""

    S.levelData = {}
    for row = 1, S.MAP_ROWS do
        S.levelData[row] = {}
        for col = 1, S.MAP_COLS do
            S.levelData[row][col] = TILE.EMPTY
        end
    end

    if data.spawn then
        S.spawnCol = data.spawn.col or 3
        S.spawnRow = data.spawn.row or (S.MAP_ROWS - 3)
        S.levelData[S.spawnRow][S.spawnCol] = TILE.SPAWN
    end

    if data.tiles then
        for _, t in ipairs(data.tiles) do
            if t.row >= 1 and t.row <= S.MAP_ROWS and t.col >= 1 and t.col <= S.MAP_COLS then
                S.levelData[t.row][t.col] = t.v
            end
        end
    end

    M.ApplyCamBound(data.camBound)
    M.ApplyPlayerParams(data.playerParams)

    FogOfWar.Deserialize(data.lightSources)
    S.lightSources = FogOfWar.GetLightSources()
    S.selectedLightIndex = 0
end

--- 应用摄像机边界
---@param bound table|nil
function M.ApplyCamBound(bound)
    if bound then
        S.camBound.left = bound.left or 1
        S.camBound.top = bound.top or 1
        S.camBound.right = bound.right or S.MAP_COLS
        S.camBound.bottom = bound.bottom or S.MAP_ROWS
    else
        S.camBound.left = 1
        S.camBound.top = 1
        S.camBound.right = S.MAP_COLS
        S.camBound.bottom = S.MAP_ROWS
    end
end

--- 应用玩家参数
---@param params table|nil
function M.ApplyPlayerParams(params)
    if params then
        S.playerParams.baseJumpGrids = params.baseJumpGrids or 3
        S.playerParams.fallJumpMultiplier = params.fallJumpMultiplier or 1.0
        S.playerParams.maxFallGrids = params.maxFallGrids or 10
        S.playerParams.maxJumpGrids = params.maxJumpGrids or 0
        S.playerParams.defaultLightDiameter = params.defaultLightDiameter or 12
        S.playerParams.cameraZoom = params.cameraZoom or 1.0
    else
        S.playerParams.baseJumpGrids = 3
        S.playerParams.fallJumpMultiplier = 1.0
        S.playerParams.maxFallGrids = 10
        S.playerParams.maxJumpGrids = 0
        S.playerParams.defaultLightDiameter = 12
        S.playerParams.cameraZoom = 1.0
    end
end

--- 恢复视口（缓存或默认）
---@param fname string
function M.RestoreViewport(fname)
    local cached = S.viewportCache[fname]
    if cached then
        S.cameraX = cached.cameraX
        S.cameraY = cached.cameraY
        S.zoomLevel = cached.zoomLevel
    else
        S.cameraX = 0
        S.cameraY = 0
        S.zoomLevel = 1.0
    end
end

-- ====================================================================
-- 重命名/删除
-- ====================================================================

--- 重命名关卡
---@param oldFile string
---@param newDisplayName string
function M.RenameLevel(oldFile, newDisplayName)
    local json = CloudStorage.Load(oldFile)
    if not json then
        S.SetMessage("文件不存在: " .. oldFile, 3.0)
        return
    end
    local ok, data = pcall(cjson.decode, json)
    if not ok or not data then
        S.SetMessage("解析失败!", 3.0)
        return
    end
    data.levelName = newDisplayName
    local newJson = cjson.encode(data)
    CloudStorage.Save(oldFile, newJson, function(saveOk, err)
        if saveOk then
            -- 如果重命名的是当前正在编辑的关卡，同步更新内存中的显示名称
            if oldFile == S.currentLevelName then
                S.currentLevelDisplayName = newDisplayName
            end
            -- 同步更新世界地图中对应节点的显示名称
            WorldMapEditor.UpdateNodeName(oldFile, newDisplayName)
            S.SetMessage("已重命名: " .. newDisplayName, 2.0)
            M.RefreshSavedLevels()
        else
            S.SetMessage("重命名失败: " .. (err or "未知错误"), 3.0)
        end
    end)
end

--- 删除关卡
---@param filename string
function M.DeleteLevel(filename)
    if not CloudStorage.Exists(filename) then
        S.SetMessage("文件不存在!", 3.0)
        return
    end
    CloudStorage.Delete(filename, function(ok, err)
        if ok then
            S.SetMessage("已删除: " .. filename, 2.0)
            if S.currentLevelName == filename then
                S.currentLevelName = ""
            end
            M.RefreshSavedLevels()
        else
            S.SetMessage("删除失败: " .. (err or "未知错误"), 3.0)
        end
    end)
end

return M
