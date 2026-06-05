-- ====================================================================
-- editor/LevelExport.lua - 关卡数据导出（云端→本地文件）
-- ====================================================================
-- 从 InputHandler.lua 提取，职责：将云端缓存导出为本地 JSON 文件
-- ====================================================================

local S = require "editor.State"

local M = {}

-- 外部依赖（Inject 注入）
local Persistence = nil
local Undo = nil

function M.Inject(deps)
    Persistence = deps.Persistence
    Undo = deps.Undo
end

--- 导出全部数据：将云端缓存直接写入本地 data/ 目录文件
function M.DoExport()
    local ok, err = pcall(function()
        local CloudStorage = require "cloud.CloudStorage"

        -- 导出前先保存当前正在编辑的关卡（避免未保存的关卡丢失）
        if Persistence then
            if S.currentLevelName == "" and S.levelData then
                -- 从未保存过的关卡，先执行"另存为新关卡"
                Persistence.SaveAsNewLevel()
                print("[Export] 自动保存为新关卡")
            elseif S.currentLevelName ~= "" and Undo and Undo.dirty then
                -- 有修改未保存的已有关卡
                Persistence.SaveLevel()
                print("[Export] 自动保存当前关卡: " .. S.currentLevelName)
            end
        end

        -- 确保目标目录存在（写入 scripts/data/ 以便 git 跟踪）
        fileSystem:CreateDir("scripts")
        fileSystem:CreateDir("scripts/data")
        fileSystem:CreateDir("scripts/data/levels")

        -- 调试：输出缓存状态
        print("[Export] CloudStorage.IsReady() = " .. tostring(CloudStorage.IsReady()))
        print("[Export] GetNextIndex() = " .. tostring(CloudStorage.GetNextIndex()))

        -- 获取各项数据
        local playerParams = CloudStorage.LoadPlayerParams()
        local worldMap = CloudStorage.LoadWorldMap()
        local nextIndex = CloudStorage.GetNextIndex()
        local levelFiles = CloudStorage.ListLevels()

        print("[Export] ListLevels 返回 " .. #levelFiles .. " 个文件")
        for i, f in ipairs(levelFiles) do
            print("[Export]   " .. i .. ": " .. f)
        end

        -- 如果缓存为空，提示用户先保存
        if #levelFiles == 0 then
            S.SetMessage("没有已保存的关卡，请先保存!", 3.0)
            print("[Export] 缓存为空，请检查：1) 是否已保存过关卡 2) CloudStorage.Init 是否完成")
            return
        end

        -- 写入 scripts/data/index.json（git 跟踪）
        local indexFile = File("scripts/data/index.json", FILE_WRITE)
        if indexFile and indexFile:IsOpen() then
            indexFile:WriteString(cjson.encode({ nextIndex = nextIndex }))
            indexFile:Close()
            print("[Export] 写入 scripts/data/index.json")
        else
            print("[Export] 无法写入 scripts/data/index.json")
        end

        -- 写入 scripts/data/player_params.json
        if playerParams then
            local ppFile = File("scripts/data/player_params.json", FILE_WRITE)
            if ppFile and ppFile:IsOpen() then
                ppFile:WriteString(cjson.encode(playerParams))
                ppFile:Close()
                print("[Export] 写入 scripts/data/player_params.json")
            end
        end

        -- 写入 scripts/data/world_map.json
        if worldMap then
            local wmFile = File("scripts/data/world_map.json", FILE_WRITE)
            if wmFile and wmFile:IsOpen() then
                wmFile:WriteString(cjson.encode(worldMap))
                wmFile:Close()
                print("[Export] 写入 scripts/data/world_map.json")
            end
        end

        -- 写入 scripts/data/levels/level_N.json
        local levelCount = 0
        for _, fname in ipairs(levelFiles) do
            local jsonStr = CloudStorage.Load(fname)
            if jsonStr then
                local path = "scripts/data/levels/" .. fname
                local lf = File(path, FILE_WRITE)
                if lf and lf:IsOpen() then
                    lf:WriteString(jsonStr)
                    lf:Close()
                    levelCount = levelCount + 1
                else
                    print("[Export] 无法写入 " .. path)
                end
            else
                print("[Export] CloudStorage.Load('" .. fname .. "') 返回 nil")
            end
        end
        print("[Export] 写入 " .. levelCount .. " 个关卡文件到 scripts/data/levels/")

        S.SetMessage("已导出 " .. levelCount .. " 个关卡到本地文件!", 3.0)
    end)

    if not ok then
        print("[Export Error] " .. tostring(err))
        S.SetMessage("导出出错: " .. tostring(err), 3.0)
    end
end

return M
