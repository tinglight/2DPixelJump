-- ====================================================================
-- CloudStorage.lua - 云端持久化存储模块
-- ====================================================================
--
-- 使用 clientCloud API 将关卡数据、玩家参数、世界地图持久化到云端，
-- 刷新页面后数据不丢失。
--
-- 云端 key 规范:
--   "editor_index"       -- 关卡索引（nextIndex）
--   "player_params"      -- 全局玩家参数
--   "world_map"          -- 世界地图连通关系
--   "level_1" ~ "level_N" -- 各关卡数据
--
-- 首次使用时从本地 data/ 目录读取默认值（随项目打包的初始配置）。
-- 接口保持不变，回调 callback(ok, err) 异步调用。
-- ====================================================================

local CloudStorage = {}

-- 内存中的关卡缓存
local cache = {
    levels = {},      -- { ["level_1.json"] = "json string", ... }
    nextIndex = 1,    -- 下一个可用编号
}

local DATA_DIR = "data"
local LEVELS_DIR = "data/levels"
local INDEX_FILE = "data/index.json"
local WORLD_MAP_FILE = "data/world_map.json"
local PLAYER_PARAMS_FILE = "data/player_params.json"

local initialized = false

-- ====================================================================
-- 内部辅助函数
-- ====================================================================

--- 从云端 key 名转为文件名: "level_1" -> "level_1.json"
local function KeyToFilename(key)
    return key .. ".json"
end

--- 从文件名转为云端 key: "level_1.json" -> "level_1"
local function FilenameToKey(fname)
    return fname:match("^(.+)%.json$") or fname
end

--- 读取项目打包的默认配置文件（通过 resource cache 读取 scripts/data/ 下的文件）
---@param path string 相对资源路径，如 "data/index.json"
---@return string|nil
local function ReadLocalFile(path)
    local file = cache:GetFile(path)
    if not file or not file:IsOpen() then return nil end
    local content = file:ReadString()
    file:Close()
    return content
end

--- 保存索引到云端
local function SaveIndex()
    clientCloud:Set("editor_index", { nextIndex = cache.nextIndex })
end

-- ====================================================================
-- 公共接口
-- ====================================================================

--- 初始化：从云端加载所有关卡数据到内存，若云端无数据则从本地读取默认值
---@param callback fun(ok: boolean, err?: string)
function CloudStorage.Init(callback)
    cache.levels = {}
    cache.nextIndex = 1

    -- 先尝试从云端读取索引，判断是否有云端数据
    clientCloud:Get("editor_index", {
        ok = function(values, iscores)
            local indexData = values.editor_index
            if indexData and indexData.nextIndex then
                -- 云端有数据，加载所有关卡
                cache.nextIndex = indexData.nextIndex
                CloudStorage._LoadAllLevelsFromCloud(callback)
            else
                -- 云端无数据，从本地文件加载初始值并同步到云端
                CloudStorage._LoadFromLocalAndSync(callback)
            end
        end,
        error = function(code, reason)
            -- 网络错误，尝试从本地文件加载（只读，不写云端）
            print("[CloudStorage] 云端读取失败，使用本地默认: " .. tostring(reason))
            CloudStorage._LoadFromLocalOnly(callback)
        end
    })
end

--- 从云端加载所有关卡（已知 nextIndex）
function CloudStorage._LoadAllLevelsFromCloud(callback)
    if cache.nextIndex <= 1 then
        -- 没有任何关卡
        initialized = true
        if callback then callback(true) end
        return
    end

    -- 构建批量读取请求
    local batch = clientCloud:BatchGet()
    for i = 1, cache.nextIndex - 1 do
        batch:Key("level_" .. i)
    end

    batch:Fetch({
        ok = function(values, iscores)
            for i = 1, cache.nextIndex - 1 do
                local key = "level_" .. i
                local data = values[key]
                if data then
                    local fname = KeyToFilename(key)
                    cache.levels[fname] = cjson.encode(data)
                end
            end
            initialized = true
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[CloudStorage] 批量读取关卡失败: " .. tostring(reason))
            -- 降级到本地
            CloudStorage._LoadFromLocalOnly(callback)
        end
    })
end

--- 从本地文件加载并同步到云端（首次使用）
function CloudStorage._LoadFromLocalAndSync(callback)
    CloudStorage._LoadFromLocalOnly(function(ok)
        if not ok then
            if callback then callback(false, "本地加载失败") end
            return
        end

        -- 将本地数据同步到云端
        local batch = clientCloud:BatchSet()
        batch:Set("editor_index", { nextIndex = cache.nextIndex })

        for fname, jsonStr in pairs(cache.levels) do
            local key = FilenameToKey(fname)
            local decodeOk, data = pcall(cjson.decode, jsonStr)
            if decodeOk and data then
                batch:Set(key, data)
            end
        end

        batch:Save("初始同步", {
            ok = function()
                print("[CloudStorage] 本地数据已同步到云端")
            end,
            error = function(code, reason)
                print("[CloudStorage] 同步到云端失败: " .. tostring(reason))
            end
        })

        -- 不等同步完成就返回，内存缓存已可用
        if callback then callback(true) end
    end)
end

--- 仅从本地文件加载（不写云端）
function CloudStorage._LoadFromLocalOnly(callback)
    cache.levels = {}
    cache.nextIndex = 1

    -- 读取索引（通过 resource cache 从 scripts/data/index.json 读取）
    local indexJson = ReadLocalFile(INDEX_FILE)
    if indexJson then
        local ok, indexData = pcall(cjson.decode, indexJson)
        if ok and indexData then
            cache.nextIndex = indexData.nextIndex or 1
        end
    end

    -- 根据 nextIndex 逐个加载关卡文件（resource cache 不支持目录扫描）
    for i = 1, cache.nextIndex - 1 do
        local fname = "level_" .. i .. ".json"
        local content = ReadLocalFile(LEVELS_DIR .. "/" .. fname)
        if content then
            cache.levels[fname] = content
        end
    end

    initialized = true
    if callback then callback(true) end
end

--- 是否已初始化完成
function CloudStorage.IsReady()
    return initialized
end

--- 检查关卡是否存在
---@param fname string
---@return boolean
function CloudStorage.Exists(fname)
    return cache.levels[fname] ~= nil
end

--- 读取关卡 JSON 字符串（同步，从内存缓存读）
---@param fname string
---@return string|nil
function CloudStorage.Load(fname)
    return cache.levels[fname]
end

--- 保存关卡（写入内存缓存 + 异步写入云端）
---@param fname string
---@param jsonStr string
---@param callback? fun(ok: boolean, err?: string)
function CloudStorage.Save(fname, jsonStr, callback)
    cache.levels[fname] = jsonStr

    -- 更新 nextIndex
    local idx = tonumber(fname:match("level_(%d+)%.json"))
    if idx and idx >= cache.nextIndex then
        cache.nextIndex = idx + 1
    end

    -- 写入云端
    local key = FilenameToKey(fname)
    local decodeOk, data = pcall(cjson.decode, jsonStr)
    if not decodeOk or not data then
        if callback then callback(false, "JSON 解码失败") end
        return
    end

    clientCloud:BatchSet()
        :Set(key, data)
        :Set("editor_index", { nextIndex = cache.nextIndex })
        :Save("保存关卡 " .. fname, {
            ok = function()
                if callback then callback(true) end
            end,
            error = function(code, reason)
                print("[CloudStorage] 云端保存失败: " .. tostring(reason))
                -- 内存缓存已更新，功能不受影响，下次保存会重试
                if callback then callback(true) end
            end
        })
end

--- 删除关卡
---@param fname string
---@param callback? fun(ok: boolean, err?: string)
function CloudStorage.Delete(fname, callback)
    if not cache.levels[fname] then
        if callback then callback(false, "文件不存在") end
        return
    end
    cache.levels[fname] = nil

    -- 云端删除（设为空表标记删除）
    local key = FilenameToKey(fname)
    clientCloud:Set(key, { _deleted = true }, {
        ok = function()
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[CloudStorage] 云端删除失败: " .. tostring(reason))
            if callback then callback(true) end
        end
    })
end

--- 获取所有已保存关卡文件名列表（排序后返回）
---@return table
function CloudStorage.ListLevels()
    local list = {}
    for fname, _ in pairs(cache.levels) do
        table.insert(list, fname)
    end
    -- 按编号排序
    table.sort(list, function(a, b)
        local idxA = tonumber(a:match("level_(%d+)%.json")) or 0
        local idxB = tonumber(b:match("level_(%d+)%.json")) or 0
        return idxA < idxB
    end)
    return list
end

--- 获取下一个可用的关卡编号
---@return number
function CloudStorage.GetNextIndex()
    return cache.nextIndex
end

-- ====================================================================
-- 全局玩家参数存储
-- ====================================================================
local playerParamsCache = nil  -- table or nil

--- 初始化全局玩家参数（从云端加载到内存）
---@param callback fun(ok: boolean, err?: string)
function CloudStorage.InitPlayerParams(callback)
    clientCloud:Get("player_params", {
        ok = function(values, iscores)
            local data = values.player_params
            if data and data.baseJumpGrids ~= nil then
                playerParamsCache = data
            else
                -- 云端无数据，从本地读默认值
                local json = ReadLocalFile(PLAYER_PARAMS_FILE)
                if json then
                    local ok2, localData = pcall(cjson.decode, json)
                    if ok2 and localData and localData.baseJumpGrids ~= nil then
                        playerParamsCache = localData
                        -- 同步到云端
                        clientCloud:Set("player_params", playerParamsCache)
                    end
                end
            end
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[CloudStorage] 读取玩家参数失败: " .. tostring(reason))
            -- 降级本地
            local json = ReadLocalFile(PLAYER_PARAMS_FILE)
            if json then
                local ok2, localData = pcall(cjson.decode, json)
                if ok2 and localData then
                    playerParamsCache = localData
                end
            end
            if callback then callback(true) end
        end
    })
end

--- 读取玩家参数（同步，从缓存）
---@return table|nil
function CloudStorage.LoadPlayerParams()
    return playerParamsCache
end

--- 保存全局玩家参数到云端
---@param params table
---@param callback? fun(ok: boolean, err?: string)
function CloudStorage.SavePlayerParams(params, callback)
    playerParamsCache = params
    clientCloud:Set("player_params", params, {
        ok = function()
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[CloudStorage] 保存玩家参数失败: " .. tostring(reason))
            if callback then callback(true) end
        end
    })
end

-- ====================================================================
-- 世界地图存储
-- ====================================================================
local worldMapCache = nil  -- table or nil

--- 加载世界地图（从云端加载到内存）
---@param callback fun(ok: boolean, err?: string)
function CloudStorage.InitWorldMap(callback)
    clientCloud:Get("world_map", {
        ok = function(values, iscores)
            local data = values.world_map
            if data and data.nodes then
                worldMapCache = data
            else
                -- 云端无数据，从本地读默认值
                local json = ReadLocalFile(WORLD_MAP_FILE)
                if json then
                    local ok2, localData = pcall(cjson.decode, json)
                    if ok2 and localData and localData.nodes then
                        worldMapCache = localData
                        -- 同步到云端
                        clientCloud:Set("world_map", worldMapCache)
                    else
                        worldMapCache = { nodes = {}, connections = {}, nextId = 1 }
                    end
                else
                    worldMapCache = { nodes = {}, connections = {}, nextId = 1 }
                end
            end
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[CloudStorage] 读取世界地图失败: " .. tostring(reason))
            local json = ReadLocalFile(WORLD_MAP_FILE)
            if json then
                local ok2, localData = pcall(cjson.decode, json)
                if ok2 and localData and localData.nodes then
                    worldMapCache = localData
                else
                    worldMapCache = { nodes = {}, connections = {}, nextId = 1 }
                end
            else
                worldMapCache = { nodes = {}, connections = {}, nextId = 1 }
            end
            if callback then callback(true) end
        end
    })
end

--- 读取世界地图数据（同步，从缓存）
---@return table|nil
function CloudStorage.LoadWorldMap()
    return worldMapCache
end

--- 保存世界地图数据到云端
---@param data table
---@param callback? fun(ok: boolean, err?: string)
function CloudStorage.SaveWorldMap(data, callback)
    worldMapCache = data
    clientCloud:Set("world_map", data, {
        ok = function()
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[CloudStorage] 保存世界地图失败: " .. tostring(reason))
            if callback then callback(true) end
        end
    })
end

-- ====================================================================
-- 导出/导入（用于剪贴板备份/恢复）
-- ====================================================================

--- 导出全部数据为一个 JSON 字符串
---@return string JSON 字符串，包含 levels/playerParams/worldMap/index
function CloudStorage.ExportAll()
    local exportData = {
        _format = "editor_export_v1",
        index = { nextIndex = cache.nextIndex },
        playerParams = playerParamsCache,
        worldMap = worldMapCache,
        levels = {},
    }

    -- 导出所有关卡（解码为 table 以避免双重编码）
    local files = CloudStorage.ListLevels()
    for _, fname in ipairs(files) do
        local json = cache.levels[fname]
        if json then
            local ok, data = pcall(cjson.decode, json)
            if ok and data then
                exportData.levels[fname] = data
            end
        end
    end

    return cjson.encode(exportData)
end

--- 从导出的 JSON 导入全部数据（覆盖云端）
---@param jsonStr string ExportAll 导出的 JSON
---@return boolean, string|nil
function CloudStorage.ImportAll(jsonStr)
    local ok, exportData = pcall(cjson.decode, jsonStr)
    if not ok or not exportData or exportData._format ~= "editor_export_v1" then
        return false, "无效的导出数据格式"
    end

    -- 导入 playerParams
    if exportData.playerParams then
        playerParamsCache = exportData.playerParams
    end

    -- 导入 worldMap
    if exportData.worldMap then
        worldMapCache = exportData.worldMap
    end

    -- 导入 levels
    if exportData.levels then
        for fname, data in pairs(exportData.levels) do
            cache.levels[fname] = cjson.encode(data)
        end
    end

    -- 导入 index
    if exportData.index then
        cache.nextIndex = exportData.index.nextIndex or cache.nextIndex
    end

    -- 批量同步到云端
    local batch = clientCloud:BatchSet()
    batch:Set("editor_index", { nextIndex = cache.nextIndex })

    if playerParamsCache then
        batch:Set("player_params", playerParamsCache)
    end
    if worldMapCache then
        batch:Set("world_map", worldMapCache)
    end

    for fname, jsonStr2 in pairs(cache.levels) do
        local key = FilenameToKey(fname)
        local decOk, data = pcall(cjson.decode, jsonStr2)
        if decOk and data then
            batch:Set(key, data)
        end
    end

    batch:Save("导入全部数据", {
        ok = function()
            print("[CloudStorage] 导入数据已同步到云端")
        end,
        error = function(code, reason)
            print("[CloudStorage] 导入同步失败: " .. tostring(reason))
        end
    })

    return true
end

return CloudStorage
