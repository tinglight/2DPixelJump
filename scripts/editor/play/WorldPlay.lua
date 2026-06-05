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
        -- 加载完当前关卡后，预加载所有相邻关卡的背景图
        M.PreloadConnectedBackgrounds()
        return true
    end

    --- 预加载所有相邻关卡的背景图到缓存
    --- 当前关卡加载完成后调用，利用游戏空闲时间完成 GPU 纹理上传
    function M.PreloadConnectedBackgrounds()
        if not S.worldPlayData or not S.worldPlayCurrentFile or not S.vg then return end
        -- 找到当前节点 ID
        local currentNodeId = nil
        for _, node in ipairs(S.worldPlayData.nodes) do
            if node.file == S.worldPlayCurrentFile then
                currentNodeId = node.id
                break
            end
        end
        if not currentNodeId then return end

        -- 收集所有相邻关卡的背景图路径
        local neededPaths = {}
        -- 保留当前关卡自身的路径
        if S.backgroundImage and S.backgroundImage ~= "" then
            neededPaths[S.backgroundImage] = true
        end

        for _, conn in ipairs(S.worldPlayData.connections) do
            if conn.fromId == currentNodeId then
                -- 找到目标关卡文件
                local targetFile = nil
                for _, node in ipairs(S.worldPlayData.nodes) do
                    if node.id == conn.toId then
                        targetFile = node.file
                        break
                    end
                end
                if targetFile then
                    -- 读取目标关卡 JSON，提取背景图路径
                    local json = M._cloudStorage.Load(targetFile)
                    if json then
                        local ok2, data = pcall(M._cjson.decode, json)
                        if ok2 and data and data.backgroundImage and data.backgroundImage ~= "" then
                            neededPaths[data.backgroundImage] = true
                        end
                    end
                end
            end
        end

        -- 释放缓存中不再需要的句柄（不在相邻列表中的）
        for path, handle in pairs(S._bgCache) do
            if not neededPaths[path] then
                nvgDeleteImage(S.vg, handle)
                S._bgCache[path] = nil
            end
        end

        -- 预加载缺失的背景图
        for path, _ in pairs(neededPaths) do
            if not S._bgCache[path] then
                S._bgCache[path] = nvgCreateImage(S.vg, path, 0)
            end
        end
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
        S.bgImageAlpha = (data.bgImageAlpha and type(data.bgImageAlpha) == "number") and data.bgImageAlpha or 0.5
        S.bgStretchToCanvas = (data.bgStretchToCanvas == true)
        -- 背景图加载：优先从预加载缓存获取句柄（相邻关卡已提前加载）
        if bgImg ~= S.backgroundImage or not S.bgImageHandle then
            -- 旧句柄如果不在缓存中才释放（缓存中的由缓存管理生命周期）
            if S.bgImageHandle and S.vg then
                local inCache = false
                for _, h in pairs(S._bgCache) do
                    if h == S.bgImageHandle then inCache = true; break end
                end
                if not inCache then
                    nvgDeleteImage(S.vg, S.bgImageHandle)
                end
                S.bgImageHandle = nil
            end
            S.backgroundImage = bgImg
            if S.vg and bgImg ~= "" then
                -- 优先从预加载缓存获取
                if S._bgCache[bgImg] then
                    S.bgImageHandle = S._bgCache[bgImg]
                else
                    -- 缓存中没有，立即创建并存入缓存
                    S.bgImageHandle = nvgCreateImage(S.vg, bgImg, 0)
                    S._bgCache[bgImg] = S.bgImageHandle
                end
            else
                S.bgImageHandle = nil
            end
        else
            S.backgroundImage = bgImg
        end

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
            -- 背景图已通过 PreloadConnectedBackgrounds 提前缓存，无需在此预加载
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
                -- 进入 hold 阶段：全黑屏等待背景图上传 GPU
                t.phase = "hold"
                t.holdTimer = 0
                t.pendingFile = nil
                t.pendingDir = nil
                t.pendingGx = nil
                t.pendingGy = nil
            end
        elseif t.phase == "hold" then
            -- 全黑屏等待，确保背景图片加载到 GPU 完成
            t.holdTimer = (t.holdTimer or 0) + dt
            if t.holdTimer >= 0.15 then
                t.phase = "fadeIn"
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
