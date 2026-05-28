-- ====================================================================
-- CloudStorage.lua - 本地文件持久化存储模块
-- ====================================================================
--
-- 将关卡数据、玩家参数、世界地图持久化到本地 data/ 目录下，
-- 文件以 JSON 格式存储，随项目代码一起提交到 git。
--
-- 存储结构:
--   data/levels/level_1.json   -- 各关卡数据
--   data/levels/level_2.json
--   data/world_map.json        -- 世界地图连通关系
--   data/player_params.json    -- 全局玩家参数
--   data/index.json            -- 关卡索引（nextIndex）
--
-- 接口保持不变，回调 callback(ok, err) 同步立即调用。
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

--- 确保目录存在
local function EnsureDir(dir)
    if not fileSystem:DirExists(dir) then
        fileSystem:CreateDir(dir)
    end
end

--- 读取文件内容
---@param path string
---@return string|nil
local function ReadFile(path)
    if not fileSystem:FileExists(path) then return nil end
    local file = File(path, FILE_READ)
    if not file or not file:IsOpen() then return nil end
    local content = file:ReadString()
    file:Close()
    return content
end

--- 写入文件内容
---@param path string
---@param content string
---@return boolean
local function WriteFile(path, content)
    local file = File(path, FILE_WRITE)
    if not file or not file:IsOpen() then return false end
    file:WriteString(content)
    file:Close()
    return true
end

--- 保存索引文件
local function SaveIndex()
    WriteFile(INDEX_FILE, cjson.encode({ nextIndex = cache.nextIndex }))
end

-- ====================================================================
-- 公共接口
-- ====================================================================

--- 初始化：从本地 data/levels/ 目录加载关卡列表到内存
---@param callback fun(ok: boolean, err?: string)
function CloudStorage.Init(callback)
    EnsureDir(DATA_DIR)
    EnsureDir(LEVELS_DIR)

    cache.levels = {}
    cache.nextIndex = 1

    -- 读取索引
    local indexJson = ReadFile(INDEX_FILE)
    if indexJson then
        local ok, indexData = pcall(cjson.decode, indexJson)
        if ok and indexData then
            cache.nextIndex = indexData.nextIndex or 1
        end
    end

    -- 扫描 levels 目录，加载所有 JSON 文件到内存
    local files = fileSystem:ScanDir(LEVELS_DIR .. "/", "*.json", SCAN_FILES, false)
    if files then
        for _, fname in ipairs(files) do
            local content = ReadFile(LEVELS_DIR .. "/" .. fname)
            if content then
                cache.levels[fname] = content
                -- 修正 nextIndex
                local idx = tonumber(fname:match("level_(%d+)%.json"))
                if idx and idx >= cache.nextIndex then
                    cache.nextIndex = idx + 1
                end
            end
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

--- 保存关卡（写入内存缓存 + 同步写入本地文件）
---@param fname string
---@param jsonStr string
---@param callback? fun(ok: boolean, err?: string)
function CloudStorage.Save(fname, jsonStr, callback)
    EnsureDir(DATA_DIR)
    EnsureDir(LEVELS_DIR)

    cache.levels[fname] = jsonStr

    -- 更新 nextIndex
    local idx = tonumber(fname:match("level_(%d+)%.json"))
    if idx and idx >= cache.nextIndex then
        cache.nextIndex = idx + 1
    end

    -- 写入文件
    local ok = WriteFile(LEVELS_DIR .. "/" .. fname, jsonStr)
    if ok then
        SaveIndex()
        if callback then callback(true) end
    else
        if callback then callback(false, "写入文件失败: " .. fname) end
    end
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

    -- 删除本地文件
    local path = LEVELS_DIR .. "/" .. fname
    if fileSystem:FileExists(path) then
        fileSystem:Delete(path)
    end

    if callback then callback(true) end
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

--- 初始化全局玩家参数（从本地文件加载到内存）
---@param callback fun(ok: boolean, err?: string)
function CloudStorage.InitPlayerParams(callback)
    EnsureDir(DATA_DIR)
    local json = ReadFile(PLAYER_PARAMS_FILE)
    if json then
        local ok, data = pcall(cjson.decode, json)
        if ok and data and data.baseJumpGrids ~= nil then
            playerParamsCache = data
        else
            playerParamsCache = nil
        end
    else
        playerParamsCache = nil
    end
    if callback then callback(true) end
end

--- 读取玩家参数（同步，从缓存）
---@return table|nil
function CloudStorage.LoadPlayerParams()
    return playerParamsCache
end

--- 保存全局玩家参数到本地文件
---@param params table
---@param callback? fun(ok: boolean, err?: string)
function CloudStorage.SavePlayerParams(params, callback)
    EnsureDir(DATA_DIR)
    playerParamsCache = params
    local ok = WriteFile(PLAYER_PARAMS_FILE, cjson.encode(params))
    if ok then
        if callback then callback(true) end
    else
        if callback then callback(false, "写入玩家参数失败") end
    end
end

-- ====================================================================
-- 世界地图存储
-- ====================================================================
local worldMapCache = nil  -- table or nil

--- 加载世界地图（从本地文件加载到内存）
---@param callback fun(ok: boolean, err?: string)
function CloudStorage.InitWorldMap(callback)
    EnsureDir(DATA_DIR)
    local json = ReadFile(WORLD_MAP_FILE)
    if json then
        local ok, data = pcall(cjson.decode, json)
        if ok and data and data.nodes then
            worldMapCache = data
        else
            worldMapCache = { nodes = {}, connections = {}, nextId = 1 }
        end
    else
        worldMapCache = { nodes = {}, connections = {}, nextId = 1 }
    end
    if callback then callback(true) end
end

--- 读取世界地图数据（同步，从缓存）
---@return table|nil
function CloudStorage.LoadWorldMap()
    return worldMapCache
end

--- 保存世界地图数据到本地文件
---@param data table
---@param callback? fun(ok: boolean, err?: string)
function CloudStorage.SaveWorldMap(data, callback)
    EnsureDir(DATA_DIR)
    worldMapCache = data
    local ok = WriteFile(WORLD_MAP_FILE, cjson.encode(data))
    if ok then
        if callback then callback(true) end
    else
        if callback then callback(false, "写入世界地图失败") end
    end
end

return CloudStorage
