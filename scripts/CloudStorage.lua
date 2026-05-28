-- ====================================================================
-- CloudStorage.lua - 云端关卡持久化存储模块
-- ====================================================================
--
-- 使用 clientCloud API 将关卡数据持久化到云端，解决 WASM 平台
-- 刷新页面后 File API 数据丢失的问题。
--
-- 设计:
--   - 所有关卡存储在一个云变量 key "editor_levels" 中 (values 表)
--   - 数据结构: { levels = { ["level_1.json"] = {...levelData...}, ... }, nextIndex = N }
--   - 提供和原 File API 类似的接口，内部自动同步到云端
--
-- 用法:
--   local CloudStorage = require "CloudStorage"
--   CloudStorage.Init(callback)         -- 初始化（从云端加载）
--   CloudStorage.Save(fname, jsonStr, callback)
--   CloudStorage.Load(fname) -> jsonStr or nil
--   CloudStorage.Delete(fname, callback)
--   CloudStorage.Exists(fname) -> bool
--   CloudStorage.ListLevels() -> { "level_1.json", ... }
-- ====================================================================

local CloudStorage = {}

-- 内存中的关卡缓存
local cache = {
    levels = {},      -- { ["level_1.json"] = "json string", ... }
    nextIndex = 1,    -- 下一个可用编号
}

local CLOUD_KEY = "editor_levels"
local initialized = false
local syncing = false

--- 将内存缓存同步到云端
---@param callback? fun(ok: boolean, err?: string)
local function SyncToCloud(callback)
    if syncing then
        -- 避免并发写入，延迟重试
        if callback then callback(false, "正在同步中") end
        return
    end
    syncing = true

    local data = {
        levels = cache.levels,
        nextIndex = cache.nextIndex,
    }

    clientCloud:Set(CLOUD_KEY, data, {
        ok = function()
            syncing = false
            if callback then callback(true) end
        end,
        error = function(code, reason)
            syncing = false
            if callback then callback(false, reason or ("错误码:" .. tostring(code))) end
        end,
        timeout = function()
            syncing = false
            if callback then callback(false, "超时") end
        end
    })
end

--- 初始化：从云端加载关卡数据到内存
---@param callback fun(ok: boolean, err?: string)
function CloudStorage.Init(callback)
    clientCloud:Get(CLOUD_KEY, {
        ok = function(values, iscores)
            local data = values[CLOUD_KEY]
            if data and type(data) == "table" then
                cache.levels = data.levels or {}
                cache.nextIndex = data.nextIndex or 1
            else
                -- 首次使用，空数据
                cache.levels = {}
                cache.nextIndex = 1
            end
            -- 修正 nextIndex：确保不会和现有关卡冲突
            for fname, _ in pairs(cache.levels) do
                local idx = tonumber(fname:match("level_(%d+)%.json"))
                if idx and idx >= cache.nextIndex then
                    cache.nextIndex = idx + 1
                end
            end
            initialized = true
            if callback then callback(true) end
        end,
        error = function(code, reason)
            -- 加载失败也标记初始化完成（使用空缓存）
            initialized = true
            cache.levels = {}
            cache.nextIndex = 1
            if callback then callback(false, reason or ("错误码:" .. tostring(code))) end
        end,
        timeout = function()
            initialized = true
            cache.levels = {}
            cache.nextIndex = 1
            if callback then callback(false, "超时") end
        end
    })
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

--- 保存关卡（写入内存缓存 + 异步同步到云端）
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
    SyncToCloud(callback)
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
    SyncToCloud(callback)
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
-- 世界地图存储（独立 cloud key）
-- ====================================================================
local WORLD_MAP_KEY = "world_map"
local worldMapCache = nil  -- table or nil
local worldMapSyncing = false

--- 同步世界地图到云端
---@param callback? fun(ok: boolean, err?: string)
local function SyncWorldMapToCloud(callback)
    if worldMapSyncing then
        if callback then callback(false, "正在同步中") end
        return
    end
    worldMapSyncing = true

    clientCloud:Set(WORLD_MAP_KEY, worldMapCache or {}, {
        ok = function()
            worldMapSyncing = false
            if callback then callback(true) end
        end,
        error = function(code, reason)
            worldMapSyncing = false
            if callback then callback(false, reason or ("错误码:" .. tostring(code))) end
        end,
        timeout = function()
            worldMapSyncing = false
            if callback then callback(false, "超时") end
        end
    })
end

--- 加载世界地图（从云端拉取到内存，异步）
---@param callback fun(ok: boolean, err?: string)
function CloudStorage.InitWorldMap(callback)
    clientCloud:Get(WORLD_MAP_KEY, {
        ok = function(values)
            local data = values[WORLD_MAP_KEY]
            if data and type(data) == "table" and data.nodes then
                worldMapCache = data
            else
                worldMapCache = { nodes = {}, connections = {}, nextId = 1 }
            end
            if callback then callback(true) end
        end,
        error = function(code, reason)
            worldMapCache = { nodes = {}, connections = {}, nextId = 1 }
            if callback then callback(false, reason or ("错误码:" .. tostring(code))) end
        end,
        timeout = function()
            worldMapCache = { nodes = {}, connections = {}, nextId = 1 }
            if callback then callback(false, "超时") end
        end
    })
end

--- 读取世界地图数据（同步，从缓存）
---@return table|nil
function CloudStorage.LoadWorldMap()
    return worldMapCache
end

--- 保存世界地图数据
---@param data table
---@param callback? fun(ok: boolean, err?: string)
function CloudStorage.SaveWorldMap(data, callback)
    worldMapCache = data
    SyncWorldMapToCloud(callback)
end

return CloudStorage
