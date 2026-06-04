------------------------------------------------------------
-- editor/play/WorldPlay.lua — 世界试玩模式（关卡切换 / 过渡动画）
------------------------------------------------------------
local WorldPlay = {}

function WorldPlay.Attach(M)

    local C = require("editor.Constants")
    local S = require("editor.State")
    local PipeSystem = require("editor.PipeSystem")
    local CrossLevel = require("editor.CrossLevel")

    local EDGE_THRESHOLD = 4

    --- 检测玩家与 camBound 边缘之间是否全部为实体方块（被墙挡住无法再靠近）
    ---@param gx number 玩家 gridX
    ---@param gy number 玩家 gridY
    ---@param direction string "left"|"right"|"up"|"down"
    ---@param ps number 玩家占据的格子数
    ---@return boolean
    local function IsAgainstBoundaryWall(gx, gy, direction, ps)
        if direction == "left" then
            local gap = gx - S.camBound.left
            if gap < 1 or gap > EDGE_THRESHOLD then return false end
            for row = gy, gy + ps - 1 do
                for col = S.camBound.left, gx - 1 do
                    if not M.IsSolid(col, row) then return false end
                end
            end
            return true
        elseif direction == "right" then
            local rightEdge = gx + ps
            local gap = S.camBound.right - rightEdge + 1
            if gap < 1 or gap > EDGE_THRESHOLD then return false end
            for row = gy, gy + ps - 1 do
                for col = rightEdge, S.camBound.right do
                    if not M.IsSolid(col, row) then return false end
                end
            end
            return true
        elseif direction == "up" then
            local gap = gy - S.camBound.top
            if gap < 1 or gap > EDGE_THRESHOLD then return false end
            for col = gx, gx + ps - 1 do
                for row = S.camBound.top, gy - 1 do
                    if not M.IsSolid(col, row) then return false end
                end
            end
            return true
        elseif direction == "down" then
            local bottomEdge = gy + ps
            local gap = S.camBound.bottom - bottomEdge + 1
            if gap < 1 or gap > EDGE_THRESHOLD then return false end
            for col = gx, gx + ps - 1 do
                for row = bottomEdge, S.camBound.bottom do
                    if not M.IsSolid(col, row) then return false end
                end
            end
            return true
        end
        return false
    end

    function M.WorldPlayLoadLevel(filename, fromDirection, prevGx, prevGy)
        local json = M._cloudStorage.Load(filename)
        if not json then return false end
        local ok2, data = pcall(M._cjson.decode, json)
        if not ok2 or not data then return false end
        M.ApplyWorldLevelData(data)
        M.PositionPlayerOnEntry(fromDirection, prevGx, prevGy)
        M.SnapCameraToPlayer()
        S.worldPlayCurrentFile = filename
        S.worldPlayCooldown = 0.5
        return true
    end

    function M.ApplyWorldLevelData(data)
        -- 先更新地图尺寸（关键！不同关卡可能有不同尺寸）
        if data.cols and data.cols >= 10 then S.MAP_COLS = data.cols end
        if data.rows and data.rows >= 5 then S.MAP_ROWS = data.rows end

        -- 用新尺寸重建 levelData
        S.levelData = {}
        for row = 1, S.MAP_ROWS do
            S.levelData[row] = {}
            for col = 1, S.MAP_COLS do
                S.levelData[row][col] = C.TILE.EMPTY
            end
        end
        if data.spawn then
            S.spawnCol = data.spawn.col or 3
            S.spawnRow = data.spawn.row or (S.MAP_ROWS - 3)
            S.levelData[S.spawnRow][S.spawnCol] = C.TILE.SPAWN
        end
        if data.tiles then
            for _, t in ipairs(data.tiles) do
                if t.row >= 1 and t.row <= S.MAP_ROWS and t.col >= 1 and t.col <= S.MAP_COLS then
                    S.levelData[t.row][t.col] = t.v
                end
            end
        end
        M.ApplyBound(data.camBound)

        -- 确保 MAP_COLS/MAP_ROWS 覆盖 camBound + 玩家尺寸
        local ps = M.PlayerGridSize()
        local needCols = S.camBound.right + ps - 1
        local needRows = S.camBound.bottom + ps - 1
        if needCols > S.MAP_COLS then
            local oldCols = S.MAP_COLS
            S.MAP_COLS = needCols
            for row = 1, S.MAP_ROWS do
                for col = oldCols + 1, S.MAP_COLS do
                    S.levelData[row][col] = C.TILE.EMPTY
                end
            end
        end
        if needRows > S.MAP_ROWS then
            local oldRows = S.MAP_ROWS
            S.MAP_ROWS = needRows
            for row = oldRows + 1, S.MAP_ROWS do
                S.levelData[row] = {}
                for col = 1, S.MAP_COLS do
                    S.levelData[row][col] = C.TILE.EMPTY
                end
            end
        end

        -- 背景图和明暗度
        local bgImg = (data.backgroundImage and data.backgroundImage ~= "") and data.backgroundImage or ""
        S.backgroundImage = bgImg
        S.bgImageAlpha = (data.bgImageAlpha and type(data.bgImageAlpha) == "number") and data.bgImageAlpha or 0.5
        S.bgStretchToCanvas = (data.bgStretchToCanvas == true)
        S.bgImageHandle = nil

        M._fogOfWar.Deserialize(data.lightSources)
        S.lightSources = M._fogOfWar.GetLightSources()

        M._fogOfWar.DeserializeZones(data.lightZones)
        S.lightZones = M._fogOfWar.GetLightZones()
        M._fogOfWar.ResetZoneState()

        PipeSystem.Init()
        CrossLevel.Clear()
    end

    function M.ApplyBound(bound)
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

        S.camBound.left = math.max(1, S.camBound.left)
        S.camBound.top = math.max(1, S.camBound.top)
        S.camBound.right = math.max(S.camBound.left, math.min(S.camBound.right, S.MAP_COLS))
        S.camBound.bottom = math.max(S.camBound.top, math.min(S.camBound.bottom, S.MAP_ROWS))

        if S.camBound.right - S.camBound.left < 1 then
            S.camBound.right = math.min(S.MAP_COLS, S.camBound.left + 1)
        end
        if S.camBound.bottom - S.camBound.top < 1 then
            S.camBound.bottom = math.min(S.MAP_ROWS, S.camBound.top + 1)
        end
    end

    function M.ApplyParams(params)
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

    function M.PositionPlayerOnEntry(fromDirection, prevGx, prevGy)
        if fromDirection == "right" then
            S.play.gridX = S.camBound.right
            S.play.gridY = prevGy or (S.spawnRow - (C.PLAYER_GRID_H - 1))
        elseif fromDirection == "left" then
            S.play.gridX = S.camBound.left
            S.play.gridY = prevGy or (S.spawnRow - (C.PLAYER_GRID_H - 1))
        elseif fromDirection == "down" then
            S.play.gridX = prevGx or S.spawnCol
            S.play.gridY = S.camBound.bottom
        elseif fromDirection == "up" then
            S.play.gridX = prevGx or S.spawnCol
            S.play.gridY = S.camBound.top
        else
            S.play.gridX = S.spawnCol
            S.play.gridY = S.spawnRow - (C.PLAYER_GRID_H - 1)
        end
        S.play.gridX = math.max(1, math.min(S.play.gridX, S.MAP_COLS))
        S.play.gridY = math.max(1, math.min(S.play.gridY, S.MAP_ROWS))
    end

    function M.SnapCameraToPlayer()
        local zoom = S.playerParams.cameraZoom or 1.0

        local boundLeftPx = (S.camBound.left - 1) * C.GRID
        local boundRightPx = S.camBound.right * C.GRID
        local viewW = S.playViewW * zoom
        local camMinX = boundLeftPx
        local camMaxX = math.max(boundLeftPx, boundRightPx - viewW)
        local targetCamX = (S.play.gridX - 1) * C.GRID - viewW * 0.35
        S.playCameraX = math.max(camMinX, math.min(targetCamX, camMaxX))

        local boundTopPx = (S.camBound.top - 1) * C.GRID
        local boundBottomPx = S.camBound.bottom * C.GRID
        local viewH = S.playViewH * zoom
        local camMinY = boundTopPx
        local camMaxY = math.max(boundTopPx, boundBottomPx - viewH)
        local targetCamY = (S.play.gridY - 1) * C.GRID - viewH * 0.5
        S.playCameraY = math.max(camMinY, math.min(targetCamY, camMaxY))
    end

    function M.WorldPlayFindConnection(direction)
        if not S.worldPlayData or not S.worldPlayCurrentFile then return nil end
        local currentNodeId = nil
        for _, node in ipairs(S.worldPlayData.nodes) do
            if node.file == S.worldPlayCurrentFile then
                currentNodeId = node.id
                break
            end
        end
        if not currentNodeId then return nil end
        for _, conn in ipairs(S.worldPlayData.connections) do
            if conn.fromId == currentNodeId and conn.direction == direction then
                for _, node in ipairs(S.worldPlayData.nodes) do
                    if node.id == conn.toId then return node.file end
                end
            end
        end
        return nil
    end

    function M.WorldPlayCheckBoundary()
        if S.worldPlayCooldown > 0 then return end
        if S.transition.active then return end
        local gx, gy = S.play.gridX, S.play.gridY
        local dir, fromDir = M.DetectBoundaryDirection(gx, gy)
        if not dir then return end
        local targetFile = M.WorldPlayFindConnection(dir)
        if targetFile then
            S.transition.active = true
            S.transition.phase = "fadeOut"
            S.transition.alpha = 0
            S.transition.pendingFile = targetFile
            S.transition.pendingDir = fromDir
            S.transition.pendingGx = gx
            S.transition.pendingGy = gy
        end
    end

    --- 更新关卡切换过渡动画（每帧调用）
    function M.UpdateTransition(dt)
        if not S.transition.active then return end

        local t = S.transition
        if t.phase == "fadeOut" then
            t.alpha = t.alpha + t.speed * dt
            if t.alpha >= 1.0 then
                t.alpha = 1.0
                if t.pendingFile then
                    local savedFallGridCount = S.play.fallGridCount or 0
                    if M.WorldPlayLoadLevel(t.pendingFile, t.pendingDir, t.pendingGx, t.pendingGy) then
                        CrossLevel.Clear()
                        S.tipPixels = {}
                        S.tipSpawnTimer = 0
                        S.playFallParticles = {}
                        M.campfireParticles = {}
                        M.campfireIgniteEffect = {}
                        S.play.fallGridCount = savedFallGridCount
                        S.play.fallTickCurrent = C.PLAY_FALL_BASE
                        S.play.collected = {}
                        S.play.switchState = {}
                        S.play.hiddenWallRevealed = {}
                        S.play.fragilePrevPlatform = nil
                        S.play.fragileGone = {}
                        S.play.fragileParticles = {}
                        CrossLevel.ApplyCrossSwitches(S.worldPlayCurrentFile)
                        M._savedEditorLightSources = M._DeepCopyLightSources(M._fogOfWar.GetLightSources())
                        M._RestoreCampfireLight()
                        M._fogOfWar.InitZoneVisibility(S.play.gridX + 1, S.play.gridY + 1)
                        S.SetMessage("进入: " .. t.pendingFile, 1.5)
                    end
                end
                t.phase = "fadeIn"
                t.pendingFile = nil
                t.pendingDir = nil
                t.pendingGx = nil
                t.pendingGy = nil
            end
        elseif t.phase == "fadeIn" then
            t.alpha = t.alpha - t.speed * dt
            if t.alpha <= 0 then
                t.alpha = 0
                t.phase = "none"
                t.active = false
            end
        end
    end

    --- 绘制关卡切换过渡遮罩
    function M.DrawTransition()
        if not S.transition.active then return end
        if S.transition.alpha <= 0 then return end
        local vg = S.vg
        local zoom = S.playerParams.cameraZoom or 1.0
        local w = S.playViewW * zoom
        local h = S.playViewH * zoom
        local a = math.floor(S.transition.alpha * 255)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, a))
        nvgFill(vg)
    end

    function M.DetectBoundaryDirection(gx, gy)
        local pressLeft = input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)
        local pressRight = input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)
        local ps = M.PlayerGridSize()

        local atLeft = gx <= S.camBound.left or IsAgainstBoundaryWall(gx, gy, "left", ps)
        if atLeft and pressLeft then return "left", "right" end

        local atRight = (gx + ps - 1 >= S.camBound.right) or IsAgainstBoundaryWall(gx, gy, "right", ps)
        if atRight and pressRight then return "right", "left" end

        local atTop = gy <= S.camBound.top or (S.play.isJumping and IsAgainstBoundaryWall(gx, gy, "up", ps))
        if atTop then return "up", "down" end

        local atBottom = (gy + ps - 1 >= S.camBound.bottom) or gy >= S.MAP_ROWS
        if atBottom then return "down", "up" end

        return nil, nil
    end

end

return WorldPlay
