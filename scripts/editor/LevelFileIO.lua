-- ====================================================================
-- editor/LevelFileIO.lua - 关卡文件导入/导出（.lua 格式）
-- ====================================================================
--
-- 导出：将云端关卡序列化为 .lua 文件写入 data/levels/ 目录
-- 导入：从 data/levels/ 读取 .lua 文件并导入为新关卡
--
-- 文件格式：return { levelName=..., cols=..., rows=..., tiles={...}, ... }
-- 索引文件：data/levels/_index.lua  列出所有已导出文件名
-- ====================================================================

local CloudStorage = require "CloudStorage"
local S = require "editor.State"

local M = {}

local LEVELS_DIR = "data/levels"
local INDEX_FILE = "data/levels/_index.lua"

-- ====================================================================
-- 内部辅助：Lua 表序列化为可读字符串
-- ====================================================================

--- 将值序列化为 Lua 源码字符串
---@param val any
---@param indent number
---@return string
local function SerializeValue(val, indent)
    local t = type(val)
    if t == "string" then
        return string.format("%q", val)
    elseif t == "number" then
        if val == math.floor(val) then
            return tostring(math.floor(val))
        end
        return tostring(val)
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "table" then
        return M._SerializeTable(val, indent)
    else
        return "nil"
    end
end

--- 序列化 table（带缩进）
---@param tbl table
---@param indent number
---@return string
function M._SerializeTable(tbl, indent)
    indent = indent or 1
    local pad = string.rep("    ", indent)
    local padEnd = string.rep("    ", indent - 1)

    -- 检查是否为纯数组
    local isArray = true
    local maxIdx = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
            isArray = false
            break
        end
        if k > maxIdx then maxIdx = k end
    end
    if isArray and maxIdx ~= #tbl then isArray = false end

    local parts = {}

    if isArray then
        -- 如果是 tiles 这种大数组，用紧凑格式
        local isCompact = #tbl > 0 and type(tbl[1]) == "table"
        if isCompact then
            -- 每个元素一行，紧凑格式
            for i, v in ipairs(tbl) do
                if type(v) == "table" then
                    -- 单行紧凑 table
                    local kvs = {}
                    -- 按固定顺序输出
                    local keys = {}
                    for k, _ in pairs(v) do keys[#keys + 1] = k end
                    table.sort(keys, function(a, b)
                        if type(a) == type(b) then return tostring(a) < tostring(b) end
                        return type(a) < type(b)
                    end)
                    for _, k in ipairs(keys) do
                        local kStr = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
                        kvs[#kvs + 1] = kStr .. " = " .. SerializeValue(v[k], indent + 1)
                    end
                    parts[#parts + 1] = pad .. "{ " .. table.concat(kvs, ", ") .. " }"
                else
                    parts[#parts + 1] = pad .. SerializeValue(v, indent + 1)
                end
            end
        else
            for i, v in ipairs(tbl) do
                parts[#parts + 1] = pad .. SerializeValue(v, indent + 1)
            end
        end
    else
        -- 键值对格式，按键名排序
        local keys = {}
        for k, _ in pairs(tbl) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

        for _, k in ipairs(keys) do
            local v = tbl[k]
            local kStr
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                kStr = k
            else
                kStr = "[" .. SerializeValue(k, 0) .. "]"
            end
            parts[#parts + 1] = pad .. kStr .. " = " .. SerializeValue(v, indent + 1)
        end
    end

    if #parts == 0 then
        return "{}"
    end

    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. padEnd .. "}"
end

-- ====================================================================
-- 目录与索引文件保证存在
-- ====================================================================

--- 确保 data/levels/ 目录存在
local function EnsureLevelsDir()
    fileSystem:CreateDir("data")
    fileSystem:CreateDir("data/levels")
end

--- 确保 _index.lua 文件存在（不存在则创建空索引）
local function EnsureIndexFile()
    EnsureLevelsDir()
    if not fileSystem:FileExists(INDEX_FILE) then
        local file = File:new(INDEX_FILE, FILE_WRITE)
        if file and file:IsOpen() then
            file:WriteString("return {}\n")
            file:Close()
        end
    end
end

--- 安全读取文本文件：先检查存在性，不存在返回 nil 不触发 ERROR
---@param path string
---@return string|nil
local function SafeReadText(path)
    if not fileSystem:FileExists(path) then
        return nil
    end
    local file = File:new(path, FILE_READ)
    if not file or not file:IsOpen() then
        return nil
    end
    local content = file:ReadString()
    file:Close()
    return content
end

-- ====================================================================
-- 读取索引文件（获取已导出的文件列表）
-- ====================================================================

--- 读取 _index.lua 获取已导出文件名列表
---@return string[] 文件名列表（不含路径和扩展名）
function M.ReadIndex()
    EnsureIndexFile()
    local content = SafeReadText(INDEX_FILE)
    if not content or content == "" then
        return {}
    end

    local fn, err = load(content, "=_index.lua", "t", {})
    if not fn then
        print("[LevelFileIO] 索引解析失败: " .. tostring(err))
        return {}
    end

    local ok, result = pcall(fn)
    if not ok or type(result) ~= "table" then
        return {}
    end
    return result
end

--- 写入索引文件
---@param list string[]
local function WriteIndex(list)
    EnsureLevelsDir()
    local lines = { "return {" }
    for _, name in ipairs(list) do
        lines[#lines + 1] = string.format("    %q,", name)
    end
    lines[#lines + 1] = "}"

    local content = table.concat(lines, "\n") .. "\n"
    local file = File:new(INDEX_FILE, FILE_WRITE)
    if file and file:IsOpen() then
        file:WriteString(content)
        file:Close()
    else
        print("[LevelFileIO] 写入索引失败")
    end
end

-- ====================================================================
-- 导出
-- ====================================================================

--- 导出指定关卡为 .lua 文件
---@param fname string 云端关卡文件名（如 "level_1.json"）
---@param exportName string 导出名称（用户自定义，不含扩展名）
---@return boolean, string|nil 成功/失败，错误信息
function M.ExportLevel(fname, exportName)
    -- 验证导出名称
    if not exportName or exportName == "" then
        return false, "导出名称不能为空"
    end

    -- 从安全字符角度清理文件名
    local safeName = exportName:gsub("[^%w_%-]", "_")
    if safeName == "" then safeName = "level" end

    -- 从云端加载关卡数据
    local json = CloudStorage.Load(fname)
    if not json then
        return false, "关卡不存在: " .. fname
    end

    local ok, data = pcall(cjson.decode, json)
    if not ok or not data then
        return false, "关卡数据解析失败"
    end

    -- 构建 .lua 文件内容
    local header = string.format(
        "-- Exported level: %s\n-- Source: %s\n-- Time: %s\n",
        data.levelName or exportName,
        fname,
        os.date("%Y-%m-%d %H:%M:%S")
    )

    local body = "return " .. M._SerializeTable(data, 1) .. "\n"
    local content = header .. body

    -- 写入文件
    EnsureLevelsDir()
    local filePath = LEVELS_DIR .. "/" .. safeName .. ".lua"
    local file = File:new(filePath, FILE_WRITE)
    if not file or not file:IsOpen() then
        return false, "无法写入文件: " .. filePath
    end
    file:WriteString(content)
    file:Close()

    -- 更新索引
    local index = M.ReadIndex()
    -- 避免重复
    local exists = false
    for _, name in ipairs(index) do
        if name == safeName then
            exists = true
            break
        end
    end
    if not exists then
        index[#index + 1] = safeName
    end
    WriteIndex(index)

    print("[LevelFileIO] 导出成功: " .. filePath)
    return true
end

--- 批量导出所有关卡
---@param exportPrefix string 导出名称前缀
---@return number 成功导出数量
function M.ExportAll(exportPrefix)
    local files = CloudStorage.ListLevels()
    local count = 0
    for i, fname in ipairs(files) do
        local name = exportPrefix .. "_" .. i
        local ok, err = M.ExportLevel(fname, name)
        if ok then
            count = count + 1
        else
            print("[LevelFileIO] 导出失败 " .. fname .. ": " .. tostring(err))
        end
    end
    return count
end

-- ====================================================================
-- 导入
-- ====================================================================

--- 获取可导入的关卡列表（从索引文件读取）
--- 自动跳过不存在的文件，并清理 stale index 条目
---@return table[] 每项 { name = "filename", displayName = "关卡名" }
function M.ListImportable()
    local index = M.ReadIndex()
    local result = {}
    local cleanIndex = {}
    local dirty = false

    for _, name in ipairs(index) do
        local filePath = LEVELS_DIR .. "/" .. name .. ".lua"
        local content = SafeReadText(filePath)
        if content and content ~= "" then
            cleanIndex[#cleanIndex + 1] = name

            -- 尝试解析获取 levelName
            local displayName = name
            local fn, _ = load(content, "=" .. name .. ".lua", "t", {})
            if fn then
                local ok2, data = pcall(fn)
                if ok2 and type(data) == "table" and data.levelName and data.levelName ~= "" then
                    displayName = data.levelName
                end
            end

            result[#result + 1] = {
                name = name,
                displayName = displayName,
                filePath = filePath,
            }
        else
            -- 文件不存在或为空，标记需要清理
            dirty = true
        end
    end

    -- 清理 stale index 条目
    if dirty then
        WriteIndex(cleanIndex)
    end

    return result
end

--- 导入一个 .lua 关卡文件到云端（作为新关卡追加到底部）
---@param name string 文件名（不含路径和扩展名）
---@param callback? fun(ok: boolean, err?: string)
function M.ImportLevel(name, callback)
    local filePath = LEVELS_DIR .. "/" .. name .. ".lua"
    local content = SafeReadText(filePath)

    if not content or content == "" then
        if callback then callback(false, "文件不存在或内容为空: " .. filePath) end
        return
    end

    -- 解析 .lua 文件
    local fn, err = load(content, "=" .. name .. ".lua", "t", {})
    if not fn then
        if callback then callback(false, "Lua 解析失败: " .. tostring(err)) end
        return
    end

    local ok, data = pcall(fn)
    if not ok or type(data) ~= "table" then
        if callback then callback(false, "执行失败或返回非 table") end
        return
    end

    -- 验证基本字段
    if not data.cols or not data.rows then
        if callback then callback(false, "缺少必要字段 (cols/rows)") end
        return
    end

    -- 处理显示名称冲突
    local importName = data.levelName or name
    local existingNames = {}
    local files = CloudStorage.ListLevels()
    for _, fname in ipairs(files) do
        local json = CloudStorage.Load(fname)
        if json then
            local ok2, existData = pcall(cjson.decode, json)
            if ok2 and existData and existData.levelName and existData.levelName ~= "" then
                existingNames[existData.levelName] = true
            end
        end
    end

    if existingNames[importName] then
        local suffix = 1
        while existingNames[importName .. "(" .. suffix .. ")"] do
            suffix = suffix + 1
        end
        data.levelName = importName .. "(" .. suffix .. ")"
    else
        data.levelName = importName
    end

    -- 作为新关卡保存到云端
    local newIdx = CloudStorage.GetNextIndex()
    local newFname = string.format("level_%d.json", newIdx)
    local jsonStr = cjson.encode(data)

    CloudStorage.Save(newFname, jsonStr, function(saveOk, saveErr)
        if saveOk then
            S.SetMessage("导入成功: " .. data.levelName, 2.5)
            if callback then callback(true) end
        else
            if callback then callback(false, "保存失败: " .. tostring(saveErr)) end
        end
    end)
end

return M
