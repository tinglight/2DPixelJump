-- ====================================================================
-- cloud_recovery.lua - 云端关卡数据诊断与恢复工具
-- ====================================================================
-- 用途：暴力扫描云端 level_1 ~ level_50，查找残留关卡数据
-- 使用方式：在游戏中通过 require 执行，结果打印到控制台
-- ====================================================================

local cjson = require "cjson"

local Recovery = {}

local MAX_SCAN = 50  -- 最大扫描范围

--- 扫描云端，查找所有残留的关卡数据
---@param callback fun(results: table) 回调，results = { found = {}, indexValue = number }
function Recovery.ScanCloud(callback)
    local results = {
        found = {},       -- { {key="level_3", data=...}, ... }
        indexValue = nil, -- 当前 editor_index 的 nextIndex
        worldMap = nil,   -- 当前 world_map 数据
    }

    -- 第一步：读取 editor_index 和 world_map
    clientCloud:Get("editor_index", {
        ok = function(values, iscores)
            local indexData = values.editor_index
            if indexData and indexData.nextIndex then
                results.indexValue = indexData.nextIndex
                print("[Recovery] 当前 editor_index.nextIndex = " .. tostring(indexData.nextIndex))
            else
                print("[Recovery] editor_index 不存在或为空")
            end
        end,
        error = function(code, reason)
            print("[Recovery] 读取 editor_index 失败: " .. tostring(reason))
        end
    })

    clientCloud:Get("world_map", {
        ok = function(values, iscores)
            local data = values.world_map
            if data and data.nodes then
                results.worldMap = data
                print("[Recovery] world_map 存在, nodes 数量: " .. #data.nodes)
            else
                print("[Recovery] world_map 不存在或为空")
            end
        end,
        error = function(code, reason)
            print("[Recovery] 读取 world_map 失败: " .. tostring(reason))
        end
    })

    -- 第二步：批量扫描 level_1 ~ level_MAX_SCAN
    local batch = clientCloud:BatchGet()
    for i = 1, MAX_SCAN do
        batch:Key("level_" .. i)
    end

    batch:Fetch({
        ok = function(values, iscores)
            print("[Recovery] ====== 云端扫描结果 ======")
            local count = 0
            for i = 1, MAX_SCAN do
                local key = "level_" .. i
                local data = values[key]
                if data then
                    -- 检查是否被标记为已删除
                    if data._deleted then
                        print(string.format("  [%s] 已标记删除", key))
                    else
                        count = count + 1
                        local levelName = data.levelName or "(无名)"
                        local tileCount = 0
                        if data.tiles then tileCount = #data.tiles end
                        print(string.format("  [%s] ✓ 找到! 名称=\"%s\", 瓦片数=%d",
                            key, levelName, tileCount))
                        table.insert(results.found, { key = key, data = data })
                    end
                end
            end
            print(string.format("[Recovery] ====== 共找到 %d 个有效关卡 ======", count))

            if count > 0 then
                print("[Recovery] 如需恢复，请调用 Recovery.RestoreAll()")
            else
                print("[Recovery] 云端没有找到残留关卡数据，数据可能已被彻底覆盖。")
            end

            if callback then callback(results) end
        end,
        error = function(code, reason)
            print("[Recovery] 批量扫描失败: " .. tostring(reason))
            if callback then callback(results) end
        end
    })
end

--- 根据扫描结果恢复关卡（修复 editor_index）
---@param scanResults table ScanCloud 返回的 results
function Recovery.RestoreFromResults(scanResults)
    if not scanResults or not scanResults.found or #scanResults.found == 0 then
        print("[Recovery] 没有可恢复的数据")
        return
    end

    -- 找出最大的 level 编号
    local maxIdx = 0
    for _, item in ipairs(scanResults.found) do
        local idx = tonumber(item.key:match("level_(%d+)"))
        if idx and idx > maxIdx then
            maxIdx = idx
        end
    end

    local newNextIndex = maxIdx + 1
    print(string.format("[Recovery] 将 editor_index.nextIndex 修复为 %d (共 %d 个关卡)",
        newNextIndex, #scanResults.found))

    -- 修复 editor_index
    clientCloud:Set("editor_index", { nextIndex = newNextIndex }, {
        ok = function()
            print("[Recovery] ✓ editor_index 已修复! 重启游戏即可看到所有关卡。")
        end,
        error = function(code, reason)
            print("[Recovery] editor_index 修复失败: " .. tostring(reason))
        end
    })
end

--- 一键扫描并恢复
function Recovery.RestoreAll()
    print("[Recovery] 开始扫描并恢复...")
    Recovery.ScanCloud(function(results)
        if #results.found > 0 then
            Recovery.RestoreFromResults(results)
        end
    end)
end

return Recovery
