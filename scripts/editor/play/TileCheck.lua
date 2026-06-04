------------------------------------------------------------
-- editor/play/TileCheck.lua — 道具与陷阱检测
------------------------------------------------------------
local C = require("editor.Constants")
local S = require("editor.State")
local TileUtils = require("editor.TileUtils")
-- FogOfWar accessed via M._fogOfWar (set by coordinator's M.Inject)
local CrossLevel = require("editor.CrossLevel")

local TileCheck = {}

---@param M table PlayMode module
function TileCheck.Attach(M)

    function M.CheckTilesOverlap()
        -- 每帧重置水状态标志（由 ProcessTileAt 重新设置）
        S.play.inWater = false
        S.play.inBlackWater = false

        local s = M.PlayerGridSize()
        for dy = 0, s - 1 do
            for dx = 0, s - 1 do
                local col = S.play.gridX + dx
                local row = S.play.gridY + dy
                M.ProcessTileAt(col, row)
            end
        end
    end

    function M.ProcessTileAt(col, row)
        if col < 1 or col > S.MAP_COLS or row < 1 or row > S.MAP_ROWS then return end
        local val = S.levelData[row][col]
        local base, group = TileUtils.GetTileType(val)
        local key = row .. "_" .. col

        if base == C.TILE.SPIKE or base == C.TILE.POISON_WATER then
            S.play.alive = false
            S.play.deathTimer = 0
        elseif base == C.TILE.WATER then
            S.play.inWater = true
        elseif base == C.TILE.BLACK_WATER then
            S.play.inBlackWater = true
        elseif base == C.TILE.GOAL then
            S.play.won = true
        elseif base == C.TILE.FUEL and not S.play.collected[key] then
            S.play.collected[key] = true
            -- 使用渐进式恢复动画
            local toRecover = math.floor(S.playTotalPixels * 0.4)
            local lost = S.playTotalPixels - S.playAlivePixels
            toRecover = math.min(toRecover, lost)
            if toRecover > 0 then
                M.StartPixelRecoverAnim(toRecover)
            end
            M.SyncFallGridCount()
            -- 触发火苗爆裂特效
            local worldX = (col - 1) * C.GRID + C.GRID * 0.5
            local worldY = (row - 1) * C.GRID + C.GRID * 0.5
            M.TriggerFuelBurst(worldX, worldY)
        elseif base == C.TILE.SWITCH and not S.play.collected[key] then
            S.play.collected[key] = true
            S.play.switchState[group] = not S.play.switchState[group]
            -- 记录到跨关卡状态（世界试玩模式）
            if S.editorMode == C.MODE_WORLDPLAY and S.worldPlayCurrentFile then
                CrossLevel.ActivateCrossSwitch(S.worldPlayCurrentFile, group)
            end
        elseif base == C.TILE.ABILITY_POINT and not S.play.collected[key] then
            S.play.collected[key] = true
            S.play.hasFireball = true
            S.SetMessage("获得火球能力!", 1.5)
        elseif base == C.TILE.HIDDEN_WALL and not S.play.hiddenWallRevealed[group] then
            S.play.hiddenWallRevealed[group] = S.play.gameTime
        elseif base == C.TILE.CHECKPOINT then
            -- FogOfWar is accessed via the upvalue injected in PlayMode's M.Inject
            local isNewBonfire = not S.checkpointActivated[key]
            local isHealthNotFull = S.playAlivePixels < S.playTotalPixels

            if isNewBonfire or isHealthNotFull then
                -- 移除之前篝火的光源（带渐出动画）
                if S.checkpointLightPos then
                    M._fogOfWar.RemoveLightAnimated(S.checkpointLightPos.col, S.checkpointLightPos.row)
                end
                -- 熄灭所有其他篝火，激活当前
                S.checkpointActivated = {}
                S.checkpointActivated[key] = true
                S.checkpointCol = col
                S.checkpointRow = row
                -- 世界试玩模式记录关卡文件名
                if S.editorMode == C.MODE_WORLDPLAY and S.worldPlayCurrentFile then
                    S.checkpointFile = S.worldPlayCurrentFile
                else
                    S.checkpointFile = S.currentLevelName or nil
                end
                -- 为篝火添加战争迷雾光源（直径35，带渐入动画，不显示提灯图片）
                local lightIdx = M._fogOfWar.AddLightAnimated(col, row, 35, 0.5)
                local light = M._fogOfWar.GetLight(lightIdx)
                if light then light.noLantern = true end
                S.checkpointLightPos = { col = col, row = row }
                S.lightSources = M._fogOfWar.GetLightSources()
                -- 补满火焰值
                M.RecoverPixels(S.playTotalPixels)
                M.SyncFallGridCount()
                S.SetMessage("篝火点燃! 火焰已补满!", 1.5)
                M.ShowBonfireMessage()
                M.TriggerCampfireIgnite(key)
                -- 世界试玩模式：仅正式游戏时保存玩家进度到云端（编辑器试玩不保存）
                if S.editorMode == C.MODE_WORLDPLAY and S.checkpointFile and S.fromMainMenu then
                    M.SavePlayerProgress()
                end
            end
        end
    end

    function M.SyncFallGridCount()
        local pixelsPerGrid = math.max(1, math.floor(S.playTotalPixels / 10 + 0.5))
        S.play.fallGridCount = math.max(0, math.floor((S.playTotalPixels - S.playAlivePixels) / pixelsPerGrid))
    end

    function M.CheckAdjacentHiddenWalls()
        local s = M.PlayerGridSize()
        local gx, gy = S.play.gridX, S.play.gridY
        M.RevealHiddenRow(gx, gy - 1, s, true)
        M.RevealHiddenRow(gx, gy + s, s, true)
        M.RevealHiddenCol(gx - 1, gy, s)
        M.RevealHiddenCol(gx + s, gy, s)
    end

    function M.RevealHiddenRow(startCol, row, count, isHorizontal)
        for dx = 0, count - 1 do
            local col = startCol + dx
            if col >= 1 and col <= S.MAP_COLS and row >= 1 and row <= S.MAP_ROWS then
                local ab, ag = TileUtils.GetTileType(S.levelData[row][col])
                if ab == C.TILE.HIDDEN_WALL and not S.play.hiddenWallRevealed[ag] then
                    S.play.hiddenWallRevealed[ag] = S.play.gameTime
                end
            end
        end
    end

    function M.RevealHiddenCol(col, startRow, count)
        for dy = 0, count - 1 do
            local row = startRow + dy
            if col >= 1 and col <= S.MAP_COLS and row >= 1 and row <= S.MAP_ROWS then
                local ab, ag = TileUtils.GetTileType(S.levelData[row][col])
                if ab == C.TILE.HIDDEN_WALL and not S.play.hiddenWallRevealed[ag] then
                    S.play.hiddenWallRevealed[ag] = S.play.gameTime
                end
            end
        end
    end

    function M.CheckTiles()
        M.CheckTilesOverlap()
        M.CheckAdjacentHiddenWalls()
        M.CheckDecorationTouch()
    end

    --- 检测玩家是否触碰了带"触碰变换"属性的装饰物
    function M.CheckDecorationTouch()
        if #S.decorations == 0 then return end
        local s = M.PlayerGridSize()
        local px = S.play.gridX
        local py = S.play.gridY

        for _, deco in ipairs(S.decorations) do
            if deco.touchTransform and deco.transformTarget and deco.transformTarget > 0 then
                local decoType = C.DECORATION_TYPES[deco.typeId]
                if not decoType then goto continueDeco end

                -- 装饰物占据的区域（以放置格为中心展开）
                local sw = (decoType.size and decoType.size.w) or 1
                local sh = (decoType.size and decoType.size.h) or 1
                local decoLeft = deco.col - math.floor((sw - 1) / 2)
                local decoTop = deco.row - math.floor((sh - 1) / 2)
                local decoRight = decoLeft + sw - 1
                local decoBottom = decoTop + sh - 1

                -- 玩家占据区域
                local playerRight = px + s - 1
                local playerBottom = py + s - 1

                -- AABB 碰撞检测
                if px <= decoRight and playerRight >= decoLeft and
                   py <= decoBottom and playerBottom >= decoTop then
                    -- 触碰！变换装饰类型
                    local targetType = C.DECORATION_TYPES[deco.transformTarget]
                    if targetType then
                        deco.typeId = deco.transformTarget
                        deco.touchTransform = false  -- 变换后不再触发
                        deco.transformTarget = 0
                    end
                end

                ::continueDeco::
            end
        end
    end

    function M.CalcJump()
        local baseJump = S.playerParams.baseJumpGrids
        local bonus = S.play.fallGridCount * S.playerParams.fallJumpMultiplier
        local jump = math.floor(baseJump + bonus + 0.5)
        -- maxJumpGrids = 0 表示无上限
        if S.playerParams.maxJumpGrids > 0 then
            jump = math.min(jump, S.playerParams.maxJumpGrids)
        end
        return jump
    end

end

return TileCheck
