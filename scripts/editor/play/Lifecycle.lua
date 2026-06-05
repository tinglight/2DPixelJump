------------------------------------------------------------
-- editor/play/Lifecycle.lua — 试玩模式生命周期（启动 / 退出 / 存档 / 关卡生成）
------------------------------------------------------------
local Lifecycle = {}

function Lifecycle.Attach(M)

    local C = require("editor.Constants")
    local S = require("editor.State")
    local Undo = require("editor.UndoSystem")
    local PipeSystem = require("editor.PipeSystem")
    local CrossLevel = require("editor.CrossLevel")

    function M.StartPlayMode()
        -- 仅从编辑模式首次进入时保存快照；R键重启时复用已有快照
        if S.editorMode ~= C.MODE_PLAY and S.editorMode ~= C.MODE_WORLDPLAY then
            M._savedEditorLightSources = M._DeepCopyLightSources(M._fogOfWar.GetLightSources())
            M._savedSpawnCol = S.spawnCol
            M._savedSpawnRow = S.spawnRow
        end
        S.editorMode = C.MODE_PLAY
        M._ResetPlayState()
        S.SetMessage("试玩中! ESC返回编辑", 2.0)
    end

    --- 退出试玩模式时恢复编辑器原始状态（所有退出路径必须调用）
    --- 试玩模式中对共享状态的修改（出生点、光源等）均为临时修改，退出时必须全部恢复。
    function M.ExitPlayMode()
        M._CleanupCheckpointLight()
        PipeSystem.StopSound()
        -- 恢复光源
        if M._savedEditorLightSources then
            local restored = M._DeepCopyLightSources(M._savedEditorLightSources)
            -- 防御性清理：确保恢复到编辑器的灯光没有试玩模式的 zone 残留标记
            for _, light in ipairs(restored) do
                light._originalDiameter = nil
            end
            M._fogOfWar.SetLightSources(restored)
            S.lightSources = M._fogOfWar.GetLightSources()
            M._savedEditorLightSources = nil
        end
        -- 恢复出生点（试玩模式中世界关卡加载/篝火存档会修改 spawnCol/spawnRow）
        if M._savedSpawnCol then
            S.spawnCol = M._savedSpawnCol
            S.spawnRow = M._savedSpawnRow
            M._savedSpawnCol = nil
            M._savedSpawnRow = nil
        end
        M._fogOfWar.ResetZoneState()
    end

    ------------------------------------------------------------
    -- 玩家进度存档
    ------------------------------------------------------------

    --- 保存玩家进度到云端（checkpoint位置 + 当前关卡文件）
    function M.SavePlayerProgress()
        local progress = {
            checkpointFile = S.checkpointFile,
            checkpointCol = S.checkpointCol,
            checkpointRow = S.checkpointRow,
        }
        clientCloud:Set("player_progress", progress, {
            ok = function()
                print("[PlayMode] Player progress saved: " .. tostring(S.checkpointFile))
            end,
            error = function(code, reason)
                print("[PlayMode] Failed to save player progress: " .. tostring(reason))
            end
        })
    end

    --- 加载玩家进度（同步回调）
    ---@param callback fun(progress: table|nil)
    function M.LoadPlayerProgress(callback)
        clientCloud:Get("player_progress", {
            ok = function(values)
                local progress = values.player_progress
                if progress and progress.checkpointFile and progress.checkpointFile ~= "" then
                    callback(progress)
                else
                    callback(nil)
                end
            end,
            error = function()
                callback(nil)
            end
        })
    end

    function M.StartWorldPlayMode()
        S.worldPlayData = M._worldMapEditor.GetMapData()
        if not S.worldPlayData or not S.worldPlayData.nodes or #S.worldPlayData.nodes == 0 then
            S.SetMessage("世界地图为空，请先添加关卡节点", 3.0)
            return
        end
        local firstNode = S.worldPlayData.nodes[1]
        if not firstNode or not firstNode.file then
            S.SetMessage("首个节点无关卡文件", 3.0)
            return
        end

        -- 保存编辑器原始出生点（在异步回调加载关卡前），退出时恢复
        M._savedSpawnCol = S.spawnCol
        M._savedSpawnRow = S.spawnRow

        -- 获取配置的初始关卡（H键设置），若有则忽略存档直接从此关卡开始
        local configuredStart = M._worldMapEditor.GetStartFile()

        M.LoadPlayerProgress(function(progress)
            -- 仅在未配置初始关卡时，才尝试从篝火存档恢复
            if not configuredStart and progress and progress.checkpointFile then
                if M._cloudStorage.Exists(progress.checkpointFile) and M.WorldPlayLoadLevel(progress.checkpointFile, nil) then
                    S.worldPlayCurrentFile = progress.checkpointFile
                    S.worldPlayCooldown = 0
                    S.editorMode = C.MODE_WORLDPLAY
                    M._savedEditorLightSources = M._DeepCopyLightSources(M._fogOfWar.GetLightSources())
                    M._ResetPlayState()
                    CrossLevel.Reset()
                    S.checkpointFile = progress.checkpointFile
                    S.checkpointCol = progress.checkpointCol
                    S.checkpointRow = progress.checkpointRow
                    S.spawnCol = progress.checkpointCol
                    S.spawnRow = progress.checkpointRow
                    S.play.gridX = S.spawnCol
                    S.play.gridY = S.spawnRow - (C.PLAYER_GRID_H - 1)
                    M.SnapCameraToPlayer()
                    local cpKey = S.checkpointRow .. "_" .. S.checkpointCol
                    S.checkpointActivated = {}
                    S.checkpointActivated[cpKey] = true
                    M._RestoreCampfireLight()
                    M._fogOfWar.InitZoneVisibility(S.play.gridX + 1, S.play.gridY + 1)
                    S.SetMessage("从篝火继续冒险...", 2.0)
                    return
                end
            end
            -- 使用配置的初始关卡，若未配置则使用第一个节点
            local startFile = configuredStart or firstNode.file
            if not M.WorldPlayLoadLevel(startFile, nil) then
                S.SetMessage("加载关卡失败: " .. startFile, 3.0)
                return
            end
            S.worldPlayCurrentFile = startFile
            S.worldPlayCooldown = 0
            S.editorMode = C.MODE_WORLDPLAY
            M._savedEditorLightSources = M._DeepCopyLightSources(M._fogOfWar.GetLightSources())
            M._ResetPlayState()
            CrossLevel.Reset()
            S.SetMessage("世界试玩中! ESC返回 | 到达边界自动切换关卡", 3.0)
        end)
    end

    ------------------------------------------------------------
    -- 随机关卡生成
    ------------------------------------------------------------

    function M.GenerateRandomLevel()
        local diff = C.DIFFICULTIES[S.currentDifficulty]
        local map, sc, sr, templateName = M._levelGenerator.GenerateValid(diff, 5, S.MAP_COLS, S.MAP_ROWS)
        for row = 1, S.MAP_ROWS do
            S.levelData[row] = {}
            for col = 1, S.MAP_COLS do
                if map[row] and map[row][col] then
                    S.levelData[row][col] = map[row][col]
                else
                    S.levelData[row][col] = C.TILE.EMPTY
                end
            end
        end
        S.spawnCol = sc
        S.spawnRow = sr
        S.camBound.left = 1
        S.camBound.top = 1
        S.camBound.right = S.MAP_COLS
        S.camBound.bottom = S.MAP_ROWS
        S.cameraX = 0
        S.currentLevelName = ""
        Undo.stack = {}
        Undo.currentAction = nil
        Undo.dirty = false
        Undo.saveTimer = 0
        M._fogOfWar.ClearAll()
        S.lightSources = M._fogOfWar.GetLightSources()
        S.selectedLightIndex = 0
        local diffName = C.DIFFICULTY_NAMES[diff] or diff
        S.SetMessage("随机[" .. diffName .. "] 模板:" .. templateName, 4.0)
    end

    function M.CycleDifficulty()
        S.currentDifficulty = S.currentDifficulty % #C.DIFFICULTIES + 1
        local diff = C.DIFFICULTIES[S.currentDifficulty]
        local diffName = C.DIFFICULTY_NAMES[diff]
        S.SetMessage("难度: " .. diffName, 2.0)
    end

end

return Lifecycle
