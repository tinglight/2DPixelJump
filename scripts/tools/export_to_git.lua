-- ====================================================================
-- tools/export_to_git.lua - 同步导出入口（独立运行）
-- ====================================================================
-- 本脚本作为 entry 构建运行，初始化 CloudStorage 后将云端数据
-- 通过 print() 输出到日志，供外部工具提取后写入 scripts/data/。
-- ====================================================================

require "LuaScripts/Utilities/Sample"

local CloudStorage = require "CloudStorage"

local function DoExportToLog()
    local playerParams = CloudStorage.LoadPlayerParams()
    local worldMap = CloudStorage.LoadWorldMap()
    local nextIndex = CloudStorage.GetNextIndex()
    local levelFiles = CloudStorage.ListLevels()

    print("[ExportToGit] nextIndex = " .. tostring(nextIndex))
    print("[ExportToGit] levels count = " .. #levelFiles)

    if #levelFiles == 0 then
        print("[ExportToGit] ERROR: 没有已保存的关卡，跳过导出")
        return false
    end

    -- 输出 index.json
    print("__EXPORT_FILE__:index.json:" .. cjson.encode({ nextIndex = nextIndex }))

    -- 输出 player_params.json
    if playerParams then
        print("__EXPORT_FILE__:player_params.json:" .. cjson.encode(playerParams))
    end

    -- 输出 world_map.json
    if worldMap then
        print("__EXPORT_FILE__:world_map.json:" .. cjson.encode(worldMap))
    end

    -- 输出各关卡文件
    for _, fname in ipairs(levelFiles) do
        local jsonStr = CloudStorage.Load(fname)
        if jsonStr then
            print("__EXPORT_FILE__:levels/" .. fname .. ":" .. jsonStr)
        end
    end

    print("[ExportToGit] ====== 导出数据输出完成 ======")
    return true
end

function Start()
    print("[ExportToGit] ====== 同步导出开始 ======")

    CloudStorage.Init(function(initOk, initErr)
        if not initOk then
            print("[ExportToGit] CloudStorage.Init 失败: " .. tostring(initErr))
            return
        end
        print("[ExportToGit] CloudStorage 初始化完成")

        CloudStorage.InitPlayerParams(function()
            CloudStorage.InitWorldMap(function()
                DoExportToLog()
            end)
        end)
    end)
end

function Stop()
end
