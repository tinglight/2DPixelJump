------------------------------------------------------------
-- editor/play/Renderer.lua — 试玩模式全部渲染函数
------------------------------------------------------------
local Renderer = {}

function Renderer.Attach(M)

    local C = require("editor.Constants")
    local S = require("editor.State")
    local TileUtils = require("editor.TileUtils")
    local FlameRenderer = require("editor.FlameRenderer")
    local SolidRenderer = require("rendering.SolidRenderer")
    local CurtainRenderer = require("rendering.CurtainRenderer")
    local PipeSystem = require("editor.PipeSystem")
    local CrossLevel = require("editor.CrossLevel")
    local FlameDashChain = require("gameplay.FlameDashChain")
    local GMTool = require("editor.GMTool")

    -- 装饰物图片句柄缓存
    local playDecoImageCache = {}

    ------------------------------------------------------------
    -- 像素字体 (5x7 bitmap)
    ------------------------------------------------------------

    local PIXEL_FONT = {
        A = { "01110", "10001", "10001", "11111", "10001", "10001", "10001" },
        B = { "11110", "10001", "10001", "11110", "10001", "10001", "11110" },
        C = { "01110", "10001", "10000", "10000", "10000", "10001", "01110" },
        D = { "11100", "10010", "10001", "10001", "10001", "10010", "11100" },
        E = { "11111", "10000", "10000", "11110", "10000", "10000", "11111" },
        F = { "11111", "10000", "10000", "11110", "10000", "10000", "10000" },
        G = { "01110", "10001", "10000", "10111", "10001", "10001", "01110" },
        H = { "10001", "10001", "10001", "11111", "10001", "10001", "10001" },
        I = { "11111", "00100", "00100", "00100", "00100", "00100", "11111" },
        K = { "10001", "10010", "10100", "11000", "10100", "10010", "10001" },
        L = { "10000", "10000", "10000", "10000", "10000", "10000", "11111" },
        M = { "10001", "11011", "10101", "10101", "10001", "10001", "10001" },
        N = { "10001", "11001", "10101", "10011", "10001", "10001", "10001" },
        O = { "01110", "10001", "10001", "10001", "10001", "10001", "01110" },
        P = { "11110", "10001", "10001", "11110", "10000", "10000", "10000" },
        R = { "11110", "10001", "10001", "11110", "10100", "10010", "10001" },
        S = { "01111", "10000", "10000", "01110", "00001", "00001", "11110" },
        T = { "11111", "00100", "00100", "00100", "00100", "00100", "00100" },
        U = { "10001", "10001", "10001", "10001", "10001", "10001", "01110" },
        W = { "10001", "10001", "10001", "10101", "10101", "11011", "10001" },
        X = { "10001", "01010", "00100", "00100", "00100", "01010", "10001" },
        Y = { "10001", "10001", "01010", "00100", "00100", "00100", "00100" },
        [" "] = { "00000", "00000", "00000", "00000", "00000", "00000", "00000" },
        [":"] = { "00000", "00100", "00100", "00000", "00100", "00100", "00000" },
    }

    --- 绘制像素字体文本（居中）
    function M.DrawPixelText(vg, text, cx, cy, pixSize, r, g, b, a)
        local gap = 1
        local charW = 5
        local charH = 7
        local totalW = #text * (charW + gap) - gap
        local startX = cx - totalW * pixSize * 0.5
        local startY = cy - charH * pixSize * 0.5

        nvgFillColor(vg, nvgRGBA(r, g, b, a))
        for ci = 1, #text do
            local ch = text:sub(ci, ci)
            local glyph = PIXEL_FONT[ch]
            if glyph then
                local ox = startX + (ci - 1) * (charW + gap) * pixSize
                for row = 1, charH do
                    local rowStr = glyph[row]
                    for col = 1, charW do
                        ---@diagnostic disable-next-line: param-type-mismatch
                        if rowStr:sub(col, col) == "1" then
                            nvgBeginPath(vg)
                            nvgRect(vg, ox + (col - 1) * pixSize, startY + (row - 1) * pixSize, pixSize, pixSize)
                            nvgFill(vg)
                        end
                    end
                end
            end
        end
    end

    ------------------------------------------------------------
    -- 主绘制入口
    ------------------------------------------------------------

    function M.Draw()
        local vg = S.vg

        SolidRenderer.SetTime(S.editorClock)
        M.DrawBackground(vg)
        local startCol, endCol = M.DrawGrid(vg)
        -- 装饰资产图片（背景上方，地块下方，被迷雾覆盖）
        if #S.decorations > 0 then
            local decoZoom = S.playerParams.cameraZoom or 1.0
            local decoViewW = S.playViewW * decoZoom
            local decoViewH = S.playViewH * decoZoom
            for _, deco in ipairs(S.decorations) do
                if not deco.handle and deco.image and deco.image ~= "" then
                    deco.handle = nvgCreateImage(vg, deco.image, 0)
                end
                if deco.handle and deco.handle > 0 then
                    local dx = (deco.col - 1) * C.GRID - S.playCameraX
                    local dy = (deco.row - 1) * C.GRID - S.playCameraY
                    local dw = (deco.w or 2) * C.GRID
                    local dh = (deco.h or 2) * C.GRID
                    if dx + dw > 0 and dx < decoViewW and dy + dh > 0 and dy < decoViewH then
                        local alpha = deco.alpha or 1.0
                        local imgPaint = nvgImagePattern(vg, dx, dy, dw, dh, 0, deco.handle, alpha)
                        nvgBeginPath(vg)
                        nvgRect(vg, dx, dy, dw, dh)
                        nvgFillPaint(vg, imgPaint)
                        nvgFill(vg)
                    end
                end
            end
        end
        M.DrawDecorations(vg, startCol, endCol)
        M.DrawTiles(vg, startCol, endCol)
        M.DrawFragileParticles(vg)
        PipeSystem.DrawParticles(vg, S.playCameraX, S.playCameraY)
        FlameRenderer.UpdateFlameAnim()
        if FlameDashChain.IsActive() then
            M.DrawDashStreakEffect(vg)
        else
            FlameRenderer.Draw()
        end
        -- 恢复闪光覆盖
        local flashIntensity = M.GetRecoverFlashIntensity()
        if flashIntensity > 0 then
            local ps = C.FLAME_CFG.pixelSize
            local N = C.FLAME_CFG.pixelGridSize
            local totalSize = N * ps
            local baseX = (S.play.gridX - 1) * C.GRID - S.playCameraX
            local baseY = (S.play.gridY - 1) * C.GRID - S.playCameraY
            local cx = baseX + totalSize * 0.5
            local cy = baseY + totalSize * 0.5
            local flashAlpha = math.floor(flashIntensity * 180)
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, totalSize * 0.7)
            nvgFillColor(vg, nvgRGBA(255, 200, 60, flashAlpha))
            nvgFill(vg)
        end
        M.DrawFuelBurst(vg, S.playCameraX, S.playCameraY)
        CrossLevel.Draw(vg, S.playCameraX, S.playCameraY)
        M.DrawFogOfWar(vg, startCol, endCol)
        M.DrawHUD(vg)
        GMTool.Draw(vg)
        M.DrawOverlays(vg)
        M.DrawTransition()
    end

    function M.DrawBackground(vg)
        local zoom = S.playerParams.cameraZoom or 1.0
        local bgW = S.playViewW * zoom
        local bgH = S.playViewH * zoom
        local bg = nvgLinearGradient(vg, 0, 0, 0, bgH,
            nvgRGBA(10, 5, 20, 255), nvgRGBA(30, 15, 40, 255))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, bgW, bgH)
        nvgFillPaint(vg, bg)
        nvgFill(vg)

        if S.backgroundImage ~= "" then
            if not S.bgImageHandle then
                S.bgImageHandle = nvgCreateImage(vg, S.backgroundImage, 0)
            end
            if S.bgImageHandle and S.bgImageHandle > 0 then
                local bx, by, bw, bh
                if S.bgStretchToCanvas then
                    bx = -S.playCameraX
                    by = -(S.playCameraY or 0)
                    bw = S.MAP_COLS * C.GRID
                    bh = S.MAP_ROWS * C.GRID
                else
                    bx = (S.camBound.left - 1) * C.GRID - S.playCameraX
                    by = (S.camBound.top - 1) * C.GRID - (S.playCameraY or 0)
                    bw = (S.camBound.right - S.camBound.left + 1) * C.GRID
                    bh = (S.camBound.bottom - S.camBound.top + 1) * C.GRID
                end
                local imgPaint = nvgImagePattern(vg, bx, by, bw, bh, 0, S.bgImageHandle, S.bgImageAlpha or 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, bx, by, bw, bh)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            end
        end
    end

    function M.DrawGrid(vg)
        local zoom = S.playerParams.cameraZoom or 1.0
        local visibleW = S.playViewW * zoom
        local visibleH = S.playViewH * zoom
        local startCol = math.max(1, math.floor(S.playCameraX / C.GRID) + 1)
        local endCol = math.min(S.MAP_COLS, startCol + math.ceil(visibleW / C.GRID) + 2)
        local startRow = math.max(1, math.floor(S.playCameraY / C.GRID) + 1)
        local endRow = math.min(S.MAP_ROWS, startRow + math.ceil(visibleH / C.GRID) + 2)

        if not S.playGridVisible then
            return startCol, endCol
        end

        nvgBeginPath(vg)
        for col = startCol, endCol + 1 do
            local x = (col - 1) * C.GRID - S.playCameraX
            nvgMoveTo(vg, x, (startRow - 1) * C.GRID - S.playCameraY)
            nvgLineTo(vg, x, endRow * C.GRID - S.playCameraY)
        end
        for row = startRow, endRow + 1 do
            local y = (row - 1) * C.GRID - S.playCameraY
            nvgMoveTo(vg, (startCol - 1) * C.GRID - S.playCameraX, y)
            nvgLineTo(vg, endCol * C.GRID - S.playCameraX, y)
        end
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 15))
        nvgStrokeWidth(vg, 0.5)
        nvgStroke(vg)

        nvgBeginPath(vg)
        for col = startCol, endCol + 1 do
            if (col - 1) % 5 == 0 then
                local x = (col - 1) * C.GRID - S.playCameraX
                nvgMoveTo(vg, x, (startRow - 1) * C.GRID - S.playCameraY)
                nvgLineTo(vg, x, endRow * C.GRID - S.playCameraY)
            end
        end
        for row = startRow, endRow + 1 do
            if (row - 1) % 5 == 0 then
                local y = (row - 1) * C.GRID - S.playCameraY
                nvgMoveTo(vg, (startCol - 1) * C.GRID - S.playCameraX, y)
                nvgLineTo(vg, endCol * C.GRID - S.playCameraX, y)
            end
        end
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 35))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        return startCol, endCol
    end

    function M.DrawTiles(vg, startCol, endCol)
        local zoom = S.playerParams.cameraZoom or 1.0
        local visibleH = S.playViewH * zoom
        local startRow = math.max(1, math.floor(S.playCameraY / C.GRID) + 1)
        local endRow = math.min(S.MAP_ROWS, startRow + math.ceil(visibleH / C.GRID) + 2)
        for row = startRow, endRow do
            for col = startCol, endCol do
                local val = S.levelData[row][col]
                if val ~= C.TILE.EMPTY and val ~= C.TILE.SPAWN then
                    local px = (col - 1) * C.GRID - S.playCameraX
                    local py = (row - 1) * C.GRID - S.playCameraY
                    local base, group = TileUtils.GetTileType(val)
                    M.DrawOneTile(vg, px, py, base, group, row, col)
                end
            end
        end
    end

    function M.DrawOneTile(vg, px, py, base, group, row, col)
        if base == C.TILE.SOLID or base == C.TILE.SOLID_PILLAR or base == C.TILE.SOLID_SEWER
            or base == C.TILE.SLOPE_TR or base == C.TILE.SLOPE_TL or base == C.TILE.SLOPE_BR or base == C.TILE.SLOPE_BL then
            M.DrawSolidTileWithLight(vg, px, py, base, row, col)
        elseif base == C.TILE.FUEL then
            M.DrawFuelTile(vg, px, py, row, col)
        elseif base == C.TILE.GOAL then
            M.DrawGoalTile(vg, px, py)
        elseif base == C.TILE.SPIKE then
            M.DrawSpikeTile(vg, px, py)
        elseif base == C.TILE.SWITCH then
            M.DrawSwitchTile(vg, px, py, group, row, col)
        elseif base == C.TILE.GATE then
            M.DrawGateTile(vg, px, py, group)
        elseif base == C.TILE.HIDDEN_WALL then
            M.DrawHiddenWallTile(vg, px, py, group, row, col)
        elseif base == C.TILE.WATER then
            M.DrawWaterTile(vg, px, py, row, col)
        elseif base == C.TILE.POISON_WATER then
            M.DrawPoisonWaterTile(vg, px, py, row, col)
        elseif base == C.TILE.BLACK_WATER then
            M.DrawBlackWaterTile(vg, px, py, row, col)
        elseif base == C.TILE.LADDER then
            M.DrawLadderTile(vg, px, py, row, col)
        elseif base == C.TILE.CHECKPOINT then
            M.DrawCheckpointTile(vg, px, py, row, col)
        elseif base == C.TILE.PIPE then
            M.DrawPipeTile(vg, px, py, row, col)
        elseif base == C.TILE.FRAGILE then
            M.DrawFragileTile(vg, px, py, row, col)
        elseif base == C.TILE.CURTAIN then
            M.DrawCurtainTile(vg, px, py, row, col)
        elseif base == C.TILE.ABILITY_POINT then
            local apKey = row .. "_" .. col
            if not S.play.collected[apKey] then
                M.DrawAbilityPointTile(vg, px, py, row, col)
            end
        end
    end

    function M.DrawSolidTile(vg, px, py)
        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + 0.5, C.GRID - 1, C.GRID - 1)
        nvgFillColor(vg, nvgRGBA(40, 45, 55, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + 0.5, C.GRID - 1, 2)
        nvgFillColor(vg, nvgRGBA(60, 70, 80, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + 0.5, 2, C.GRID - 1)
        nvgFillColor(vg, nvgRGBA(55, 60, 70, 255))
        nvgFill(vg)
    end

    function M.DrawSolidTileWithLight(vg, px, py, tileType, row, col)
        local playerCol = S.play.gridX
        local playerRow = S.play.gridY + 1
        local flameRatio = S.playAlivePixels / math.max(1, S.playTotalPixels)
        local playerRadius = (S.playerParams and S.playerParams.defaultLightDiameter or 6) * 0.5 * flameRatio
        local pLit, pLdx, pLdy = SolidRenderer.CalcPlayerLightDirection(col, row, playerCol, playerRow, playerRadius)
        local sLit, sLdx, sLdy = SolidRenderer.CalcLightDirection(col, row, S.lightSources)
        local totalLit = math.min(1.0, pLit + sLit)
        local totalLdx = pLdx * pLit + sLdx * sLit
        local totalLdy = pLdy * pLit + sLdy * sLit
        local len = math.sqrt(totalLdx * totalLdx + totalLdy * totalLdy)
        if len > 0.01 then
            totalLdx = totalLdx / len
            totalLdy = totalLdy / len
        end
        local neighbors = {
            top    = M.IsSolidAt(row - 1, col),
            bottom = M.IsSolidAt(row + 1, col),
            left   = M.IsSolidAt(row, col - 1),
            right  = M.IsSolidAt(row, col + 1),
            pillarTop    = M.IsPillarAt(row - 1, col),
            pillarBottom = M.IsPillarAt(row + 1, col),
            pillarLeft   = M.IsPillarAt(row, col - 1),
            pillarRight  = M.IsPillarAt(row, col + 1),
        }
        SolidRenderer.DrawSolid(vg, tileType, px, py, C.GRID, totalLit, totalLdx, totalLdy, col, row, neighbors)
    end

    function M.DrawAbilityPointTile(vg, px, py, row, col)
        local GRID = C.GRID
        local ps = 3
        local t = S.playGameTime or 0
        row = row or 1
        col = col or 1

        local shape = {
            {0,0,1,1,1,0,0},
            {0,1,1,1,1,1,0},
            {1,1,1,1,1,1,1},
            {1,1,1,1,1,1,1},
            {1,1,1,1,1,1,1},
            {0,1,1,1,1,1,0},
            {0,0,1,1,1,0,0},
        }

        local frame = math.floor(t * 6 + col * 1.3) % 4
        local coreFrames = {
            {{0,0,0,0,0,0,0},{0,0,0,1,0,0,0},{0,0,1,1,1,0,0},{0,0,1,1,0,0,0},{0,0,0,1,0,0,0},{0,0,0,0,0,0,0},{0,0,0,0,0,0,0}},
            {{0,0,0,0,0,0,0},{0,0,0,0,0,0,0},{0,0,1,1,0,0,0},{0,0,1,1,1,0,0},{0,0,0,1,1,0,0},{0,0,0,0,0,0,0},{0,0,0,0,0,0,0}},
            {{0,0,0,0,0,0,0},{0,0,0,0,0,0,0},{0,0,0,1,0,0,0},{0,0,0,1,1,0,0},{0,0,1,1,1,0,0},{0,0,0,1,0,0,0},{0,0,0,0,0,0,0}},
            {{0,0,0,0,0,0,0},{0,0,0,0,0,0,0},{0,0,0,1,1,0,0},{0,0,1,1,1,0,0},{0,0,1,1,0,0,0},{0,0,0,0,0,0,0},{0,0,0,0,0,0,0}},
        }
        local coreMask = coreFrames[frame + 1]

        local floatY = math.sin(t * 3 + col * 2.1) * 1.5
        local totalSize = 7 * ps
        local startX = px + (GRID - totalSize) * 0.5
        local startY = py + (GRID - totalSize) * 0.5 + floatY

        local glowPulse = math.sin(t * 5 + col * 2.7) * 0.3 + 0.7
        nvgBeginPath(vg)
        nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5 + floatY, totalSize * 0.6 * glowPulse)
        nvgFillColor(vg, nvgRGBA(255, 140, 30, math.floor(50 * glowPulse)))
        nvgFill(vg)

        for r = 1, 7 do
            for c = 1, 7 do
                if shape[r][c] == 1 then
                    local drawX = startX + (c - 1) * ps
                    local drawY = startY + (r - 1) * ps
                    local dx = c - 4
                    local dy = r - 4
                    local dist = math.sqrt(dx * dx + dy * dy)
                    local cr, cg, cb
                    if coreMask[r][c] == 1 then
                        cr, cg, cb = 255, 255, 220
                    elseif dist < 1.5 then
                        cr, cg, cb = 255, 230, 80
                    elseif dist < 2.5 then
                        cr, cg, cb = 255, 160, 40
                    else
                        cr, cg, cb = 230, 80, 20
                    end
                    local flick = math.sin(t * 10 + r * 3 + c * 5) * 0.12 + 0.88
                    cr = math.min(255, math.floor(cr * flick))
                    cg = math.min(255, math.floor(cg * flick))
                    cb = math.min(255, math.floor(cb * flick))
                    nvgBeginPath(vg)
                    nvgRect(vg, drawX, drawY, ps, ps)
                    nvgFillColor(vg, nvgRGBA(cr, cg, cb, 255))
                    nvgFill(vg)
                end
            end
        end

        local sparkFrame = math.floor(t * 10 + col * 3) % 5
        if sparkFrame < 3 then
            local sparkX = startX + 3 * ps + math.sin(t * 7 + col) * ps
            local sparkY = startY - ps - sparkFrame * ps * 0.6
            local sparkAlpha = math.floor((1 - sparkFrame / 3) * 220)
            nvgBeginPath(vg)
            nvgRect(vg, sparkX, sparkY, ps, ps)
            nvgFillColor(vg, nvgRGBA(255, 240, 100, sparkAlpha))
            nvgFill(vg)
        end

        local sideAngle = t * 4 + col * 1.5
        for i = 1, 2 do
            local angle = sideAngle + i * math.pi
            local sparkDist = totalSize * 0.5 + ps
            local sx = px + GRID * 0.5 + math.cos(angle) * sparkDist
            local sy = py + GRID * 0.5 + floatY + math.sin(angle) * sparkDist * 0.6
            local sAlpha = math.floor(math.abs(math.sin(angle + t * 3)) * 180)
            nvgBeginPath(vg)
            nvgRect(vg, sx, sy, ps, ps)
            nvgFillColor(vg, nvgRGBA(255, 200, 60, sAlpha))
            nvgFill(vg)
        end
    end

    function M.DrawCurtainTile(vg, px, py, row, col)
        local playerCol = S.play.gridX
        local playerRow = S.play.gridY + 1
        local flameRatio = S.playAlivePixels / math.max(1, S.playTotalPixels)
        local playerRadius = (S.playerParams and S.playerParams.defaultLightDiameter or 6) * 0.5 * flameRatio
        local pLit, pLdx, pLdy = SolidRenderer.CalcPlayerLightDirection(col, row, playerCol, playerRow, playerRadius)
        local sLit, sLdx, sLdy = SolidRenderer.CalcLightDirection(col, row, S.lightSources)
        local totalLit = math.min(1.0, pLit + sLit)
        local totalLdx = pLdx * pLit + sLdx * sLit
        local totalLdy = pLdy * pLit + sLdy * sLit
        local len = math.sqrt(totalLdx * totalLdx + totalLdy * totalLdy)
        if len > 0.01 then
            totalLdx = totalLdx / len
            totalLdy = totalLdy / len
        end

        local hasAbove = (row > 1) and (TileUtils.GetTileType(S.levelData[row - 1][col]) == C.TILE.CURTAIN)
        local hasBelow = (row < S.MAP_ROWS) and (TileUtils.GetTileType(S.levelData[row + 1][col]) == C.TILE.CURTAIN)

        CurtainRenderer.DrawCurtain(vg, px, py, C.GRID, totalLit, totalLdx, totalLdy,
            col, row, S.playGameTime or 0, hasAbove, hasBelow)

        local gx = S.play.gridX
        local gy = S.play.gridY
        local ps = M.PlayerGridSize()
        if col >= gx and col < gx + ps and row >= gy and row < gy + ps then
            CurtainRenderer.TriggerSway(col, row, 1.2)
            CurtainRenderer.PropagateSwayToNeighbors(col, row, 1.0,
                S.levelData, C.TILE, TileUtils.GetTileType)
        end
    end

    function M.DrawFuelTile(vg, px, py, row, col)
        local key = row .. "_" .. col
        if S.play.collected[key] then return end
        local GRID = C.GRID
        local ps = 2
        local t = S.playGameTime or 0
        local frame = math.floor(t * 6 + col * 1.3) % 3
        local shapes = {
            {{0,0,1,0,0},{0,1,1,0,0},{0,1,1,1,0},{1,1,1,1,0},{1,1,1,1,1},{0,1,1,1,0},{0,0,1,0,0}},
            {{0,0,0,1,0},{0,0,1,1,0},{0,1,1,1,0},{0,1,1,1,1},{1,1,1,1,0},{0,1,1,1,0},{0,0,1,0,0}},
            {{0,1,0,0,0},{0,1,1,0,0},{1,1,1,0,0},{1,1,1,1,0},{0,1,1,1,1},{0,1,1,1,0},{0,0,1,0,0}},
        }
        local shape = shapes[frame + 1]
        local colors = {
            {255, 255, 180},{255, 230, 100},{255, 190, 50},
            {255, 150, 30},{255, 120, 20},{255, 90, 10},{200, 60, 5},
        }
        local floatY = math.sin(t * 4 + col * 2.3) * 1.5
        local startX = px + (GRID - 5 * ps) * 0.5
        local startY = py + (GRID - 7 * ps) * 0.5 + floatY

        local glowFlicker = math.sin(t * 7 + col * 3.1) * 0.3 + 0.7
        nvgBeginPath(vg)
        nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5 + floatY, 7 * glowFlicker)
        nvgFillColor(vg, nvgRGBA(255, 150, 30, math.floor(35 * glowFlicker)))
        nvgFill(vg)

        for r = 1, 7 do
            for c = 1, 5 do
                if shape[r][c] == 1 then
                    local drawX = startX + (c - 1) * ps
                    local drawY = startY + (r - 1) * ps
                    local baseColor = colors[r]
                    local flick = math.sin(t * 10 + r * 3 + c * 5) * 0.15 + 0.85
                    local cr = math.min(255, math.floor(baseColor[1] * flick))
                    local cg = math.min(255, math.floor(baseColor[2] * flick))
                    local cb = math.min(255, math.floor(baseColor[3] * flick))
                    nvgBeginPath(vg)
                    nvgRect(vg, drawX, drawY, ps, ps)
                    nvgFillColor(vg, nvgRGBA(cr, cg, cb, 255))
                    nvgFill(vg)
                end
            end
        end

        local sparkPhase = math.floor(t * 12 + col * 5) % 6
        if sparkPhase < 3 then
            local sparkX = startX + 2 * ps + math.sin(t * 8 + col) * ps
            local sparkY = startY - ps - sparkPhase * ps * 0.5
            local sparkAlpha = math.floor((1 - sparkPhase / 3) * 200)
            nvgBeginPath(vg)
            nvgRect(vg, sparkX, sparkY, ps, ps)
            nvgFillColor(vg, nvgRGBA(255, 240, 100, sparkAlpha))
            nvgFill(vg)
        end
    end

    function M.DrawGoalTile(vg, px, py)
        nvgBeginPath(vg)
        nvgRect(vg, px + 7, py, 2, C.GRID)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + 9, py + 2)
        nvgLineTo(vg, px + 9 + 6, py + 5)
        nvgLineTo(vg, px + 9, py + 8)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(100, 255, 100, 255))
        nvgFill(vg)
    end

    function M.DrawSpikeTile(vg, px, py)
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + 2, py + C.GRID - 2)
        nvgLineTo(vg, px + C.GRID * 0.5, py + 2)
        nvgLineTo(vg, px + C.GRID - 2, py + C.GRID - 2)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(200, 30, 30, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + C.GRID * 0.5 - 1, py + 3)
        nvgLineTo(vg, px + C.GRID * 0.5, py + 2)
        nvgLineTo(vg, px + C.GRID * 0.5 + 1, py + 3)
        nvgStrokeColor(vg, nvgRGBA(255, 180, 180, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end

    function M.DrawSwitchTile(vg, px, py, group, row, col)
        local key = row .. "_" .. col
        local gc = C.GROUP_COLORS[group] or C.GROUP_COLORS[1]
        local activated = S.play.collected[key]
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + 3, py + C.GRID - 5, C.GRID - 6, 4, 1)
        nvgFillColor(vg, nvgRGBA(80, 80, 80, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, px + C.GRID * 0.5, py + C.GRID * 0.5, 5)
        if activated then
            nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 80))
        else
            nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
        end
        nvgFill(vg)
        if not activated then
            nvgBeginPath(vg)
            nvgRect(vg, px + C.GRID * 0.5 - 1, py + 2, 2, 6)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgFill(vg)
        end
    end

    function M.DrawGateTile(vg, px, py, group)
        local gc = C.GROUP_COLORS[group] or C.GROUP_COLORS[1]
        local open = S.play.switchState[group]
        if not open then
            nvgBeginPath(vg)
            nvgRect(vg, px + 1, py, C.GRID - 2, C.GRID)
            nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 180))
            nvgFill(vg)
            for dx = 0, 2 do
                nvgBeginPath(vg)
                nvgRect(vg, px + 3 + dx * 5, py + 2, 2, C.GRID - 4)
                nvgFillColor(vg, nvgRGBA(
                    math.floor(gc[1] * 0.3),
                    math.floor(gc[2] * 0.3),
                    math.floor(gc[3] * 0.3), 255))
                nvgFill(vg)
            end
        else
            nvgBeginPath(vg)
            nvgRect(vg, px + 1, py, C.GRID - 2, C.GRID)
            nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 50))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
    end

    function M.DrawHiddenWallTile(vg, px, py, group, row, col)
        local revealTime = S.play.hiddenWallRevealed[group]
        local alpha = 1.0
        if revealTime then
            local elapsed = S.play.gameTime - revealTime
            if elapsed >= C.HIDDEN_WALL_FADE_DURATION then
                return
            end
            alpha = 1.0 - (elapsed / C.HIDDEN_WALL_FADE_DURATION)
        end
        if alpha < 1.0 then
            nvgGlobalAlpha(vg, alpha)
        end
        if row and col then
            M.DrawSolidTileWithLight(vg, px, py, C.TILE.SOLID, row, col)
        else
            M.DrawSolidTile(vg, px, py)
        end
        if alpha < 1.0 then
            nvgGlobalAlpha(vg, 1.0)
        end
    end

    function M.DrawWaterTile(vg, px, py, row, col)
        local t = S.playGameTime
        local G = C.GRID
        local worldX = (col - 1) * G
        local hasWaterAbove = false
        if row > 1 and S.levelData[row - 1] then
            local aboveVal = S.levelData[row - 1][col]
            if aboveVal then
                local aboveBase = TileUtils.GetTileType(aboveVal)
                if aboveBase == C.TILE.WATER then hasWaterAbove = true end
            end
        end
        if not hasWaterAbove then
            local freq = 0.35
            for layer = 1, 3 do
                local speed = 2.5 + layer * 0.8
                local amp = 1.5 - layer * 0.3
                local yBase = py + 2 + layer * 3.5
                local phase = t * speed + layer * 2.1
                nvgBeginPath(vg)
                nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
                for sx = 1, 4 do
                    local localX = sx * (G / 4)
                    nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
                end
                nvgLineTo(vg, px + G, py + G)
                nvgLineTo(vg, px, py + G)
                nvgClosePath(vg)
                local a = math.floor(40 + layer * 15)
                nvgFillColor(vg, nvgRGBA(40 + layer * 20, 100 + layer * 25, 240, a))
                nvgFill(vg)
            end
        else
            nvgBeginPath(vg)
            nvgRect(vg, px, py, G, G)
            nvgFillColor(vg, nvgRGBA(20, 60, 160, 180))
            nvgFill(vg)
            local freq = 0.25
            for layer = 1, 2 do
                local speed = 1.0 + layer * 0.3
                local amp = 0.8
                local yBase = py + G * (0.3 + layer * 0.25)
                local phase = t * speed + row * 1.7 + layer * 3.0
                nvgBeginPath(vg)
                nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
                for sx = 1, 4 do
                    local localX = sx * (G / 4)
                    nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
                end
                nvgLineTo(vg, px + G, yBase + math.sin(phase + (worldX + G) * freq) * amp - 1)
                nvgLineTo(vg, px + G, yBase + 2)
                nvgLineTo(vg, px, yBase + 2)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(30 + layer * 15, 80 + layer * 20, 220, 30 + layer * 12))
                nvgFill(vg)
            end
        end
        local sparkTopY = hasWaterAbove and 2 or math.floor(G * 0.55)
        local sparkRangeH = G - sparkTopY - 2
        local seed = col * 7 + row * 13
        for i = 1, 3 do
            local phase_i = t * (3.0 + i * 0.7) + seed + i * 5.3
            local sparkAlpha = math.sin(phase_i) * 0.5 + 0.5
            if sparkAlpha > 0.3 then
                local sx = px + 2 + math.fmod(seed * i * 3.7, G - 4)
                local sy = py + sparkTopY + math.fmod(seed * i * 2.3, sparkRangeH)
                nvgBeginPath(vg)
                nvgRect(vg, sx, sy, 1, 1)
                nvgFillColor(vg, nvgRGBA(150, 220, 255, math.floor(200 * sparkAlpha)))
                nvgFill(vg)
            end
        end
    end

    function M.DrawPoisonWaterTile(vg, px, py, row, col)
        local t = S.playGameTime
        local G = C.GRID
        local worldX = (col - 1) * G
        local hasWaterAbove = false
        if row > 1 and S.levelData[row - 1] then
            local aboveVal = S.levelData[row - 1][col]
            if aboveVal then
                local aboveBase = TileUtils.GetTileType(aboveVal)
                if aboveBase == C.TILE.POISON_WATER then hasWaterAbove = true end
            end
        end
        if not hasWaterAbove then
            local freq = 0.4
            for layer = 1, 3 do
                local speed = 2.0 + layer * 0.6
                local amp = 1.8 - layer * 0.4
                local yBase = py + 2 + layer * 3.5
                local phase = t * speed + layer * 1.9
                nvgBeginPath(vg)
                nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
                for sx = 1, 4 do
                    local localX = sx * (G / 4)
                    nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
                end
                nvgLineTo(vg, px + G, py + G)
                nvgLineTo(vg, px, py + G)
                nvgClosePath(vg)
                local a = math.floor(35 + layer * 18)
                nvgFillColor(vg, nvgRGBA(20 + layer * 10, 140 + layer * 30, 40 + layer * 10, a))
                nvgFill(vg)
            end
        else
            nvgBeginPath(vg)
            nvgRect(vg, px, py, G, G)
            nvgFillColor(vg, nvgRGBA(10, 100, 25, 190))
            nvgFill(vg)
            local freq = 0.3
            for layer = 1, 2 do
                local speed = 0.8 + layer * 0.3
                local amp = 0.7
                local yBase = py + G * (0.3 + layer * 0.25)
                local phase = t * speed + row * 1.5 + layer * 2.7
                nvgBeginPath(vg)
                nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
                for sx = 1, 4 do
                    local localX = sx * (G / 4)
                    nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
                end
                nvgLineTo(vg, px + G, yBase + math.sin(phase + (worldX + G) * freq) * amp - 1)
                nvgLineTo(vg, px + G, yBase + 2)
                nvgLineTo(vg, px, yBase + 2)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(15 + layer * 8, 120 + layer * 20, 30 + layer * 8, 30 + layer * 12))
                nvgFill(vg)
            end
        end
        local sparkTopY = hasWaterAbove and 1 or math.floor(G * 0.55)
        local sparkRangeH = G - sparkTopY - 2
        local seed = col * 11 + row * 17
        for i = 1, 4 do
            local phase_i = t * (3.5 + i * 0.9) + seed + i * 4.1
            local sparkAlpha = math.sin(phase_i) * 0.5 + 0.5
            if sparkAlpha > 0.2 then
                local sx = px + 1 + math.fmod(seed * i * 2.9, G - 3)
                local sy = py + sparkTopY + math.fmod(seed * i * 1.7, sparkRangeH)
                nvgBeginPath(vg)
                nvgRect(vg, sx, sy, 1, 1)
                nvgFillColor(vg, nvgRGBA(120, 255, 130, math.floor(230 * sparkAlpha)))
                nvgFill(vg)
            end
        end
    end

    function M.DrawBlackWaterTile(vg, px, py, row, col)
        local t = S.playGameTime
        local G = C.GRID
        local worldX = (col - 1) * G
        local hasWaterAbove = false
        if row > 1 and S.levelData[row - 1] then
            local aboveVal = S.levelData[row - 1][col]
            if aboveVal then
                local aboveBase = TileUtils.GetTileType(aboveVal)
                if aboveBase == C.TILE.BLACK_WATER then hasWaterAbove = true end
            end
        end
        if not hasWaterAbove then
            local freq = 0.28
            for layer = 1, 2 do
                local speed = 1.2 + layer * 0.4
                local amp = 1.2 - layer * 0.3
                local yBase = py + 3 + layer * 4.5
                local phase = t * speed + layer * 2.5
                nvgBeginPath(vg)
                nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
                for sx = 1, 4 do
                    local localX = sx * (G / 4)
                    nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
                end
                nvgLineTo(vg, px + G, py + G)
                nvgLineTo(vg, px, py + G)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(40 + layer * 5, 40 + layer * 5, 50 + layer * 5, 80 + layer * 30))
                nvgFill(vg)
            end
        else
            nvgBeginPath(vg)
            nvgRect(vg, px, py, G, G)
            nvgFillColor(vg, nvgRGBA(30, 30, 38, 220))
            nvgFill(vg)
            local freq = 0.2
            local speed = 0.6
            local amp = 0.5
            local yBase = py + G * 0.5
            local phase = t * speed + row * 1.2 + 4.0
            nvgBeginPath(vg)
            nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
            for sx = 1, 4 do
                local localX = sx * (G / 4)
                nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
            end
            nvgLineTo(vg, px + G, yBase + math.sin(phase + (worldX + G) * freq) * amp - 1)
            nvgLineTo(vg, px + G, yBase + 2)
            nvgLineTo(vg, px, yBase + 2)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(38, 38, 48, 40))
            nvgFill(vg)
        end
        local sparkTopY = hasWaterAbove and 3 or math.floor(G * 0.6)
        local sparkRangeH = G - sparkTopY - 3
        local seed = col * 5 + row * 9
        for i = 1, 2 do
            local phase_i = t * (1.8 + i * 0.5) + seed + i * 6.7
            local sparkAlpha = math.sin(phase_i) * 0.4 + 0.4
            if sparkAlpha > 0.35 then
                local sx = px + 3 + math.fmod(seed * i * 3.1, G - 6)
                local sy = py + sparkTopY + math.fmod(seed * i * 2.7, sparkRangeH)
                nvgBeginPath(vg)
                nvgRect(vg, sx, sy, 1, 1)
                nvgFillColor(vg, nvgRGBA(140, 140, 160, math.floor(120 * sparkAlpha)))
                nvgFill(vg)
            end
        end
    end

    function M.DrawLadderTile(vg, px, py, row, col)
        if col > 1 then
            local leftVal = S.levelData[row][col - 1]
            local leftBase = TileUtils.GetTileType(leftVal)
            if leftBase == C.TILE.LADDER then return end
        end

        local G = C.GRID
        local W = G * 2
        local P = 2

        local darkWood   = nvgRGBA(58, 40, 22, 255)
        local midWood    = nvgRGBA(82, 55, 30, 255)
        local hiWood     = nvgRGBA(105, 72, 38, 255)
        local rungMain   = nvgRGBA(95, 65, 35, 255)
        local rungHi     = nvgRGBA(120, 85, 48, 255)
        local shadowWood = nvgRGBA(35, 24, 12, 255)
        local moss1      = nvgRGBA(40, 85, 30, 255)
        local moss2      = nvgRGBA(58, 110, 42, 220)
        local vine       = nvgRGBA(32, 70, 28, 240)
        local decay      = nvgRGBA(50, 45, 25, 200)

        local lx = px
        local ly = py

        local function pix(cx, cy, color)
            nvgBeginPath(vg) nvgRect(vg, lx + cx * P, ly + cy * P, P, P)
            nvgFillColor(vg, color) nvgFill(vg)
        end

        for r = 0, 7 do
            pix(1, r, midWood)
            pix(2, r, darkWood)
        end
        pix(1, 0, hiWood) pix(1, 2, hiWood) pix(1, 5, hiWood)
        pix(2, 3, shadowWood) pix(1, 6, shadowWood)

        for r = 0, 7 do
            pix(13, r, darkWood)
            pix(14, r, midWood)
        end
        pix(14, 1, hiWood) pix(14, 4, hiWood) pix(14, 6, hiWood)
        pix(13, 2, shadowWood) pix(14, 5, shadowWood)

        for c = 3, 12 do pix(c, 2, rungMain) end
        pix(4, 2, rungHi) pix(6, 2, rungHi) pix(9, 2, rungHi) pix(11, 2, rungHi)
        for c = 3, 12 do pix(c, 3, shadowWood) end

        for c = 3, 12 do pix(c, 5, rungMain) end
        pix(3, 5, rungHi) pix(5, 5, rungHi) pix(8, 5, rungHi) pix(10, 5, rungHi)
        for c = 3, 12 do pix(c, 6, shadowWood) end

        pix(0, 0, moss1) pix(1, 0, moss2) pix(0, 1, moss2)
        pix(15, 6, vine) pix(15, 7, vine) pix(14, 7, moss2)
        pix(5, 2, moss1) pix(7, 5, moss1)
        pix(9, 5, decay) pix(2, 4, decay) pix(13, 6, decay)
        pix(0, 4, vine) pix(0, 5, moss2)
    end

    function M.DrawFogOfWar(vg, startCol, endCol)
        local sources = M._fogOfWar.GetLightSources()
        local playerLightIdx = nil
        local flameRatio = S.playAlivePixels / math.max(1, S.playTotalPixels)
        local playerDiameter = math.max(3, S.playerParams.defaultLightDiameter * flameRatio)
        if playerDiameter >= 1 then
            local playerS = M.PlayerGridSize()
            local lightCol = S.play.gridX + math.floor(playerS * 0.5)
            local lightRow = S.play.gridY + math.floor(playerS * 0.5)
            table.insert(sources, {
                col = lightCol,
                row = lightRow,
                diameter = playerDiameter,
                feather = 0.5,
            })
            playerLightIdx = #sources
        end

        M._fogOfWar.SetLightSources(sources)
        local zoom = S.playerParams.cameraZoom or 1.0
        local fogVisibleH = S.playViewH * zoom
        local fogStartRow = math.max(1, math.floor(S.playCameraY / C.GRID))
        local fogEndRow = math.min(S.MAP_ROWS, fogStartRow + math.ceil(fogVisibleH / C.GRID) + 3)
        M._fogOfWar.Draw(vg, {
            gridSize = C.GRID,
            startCol = startCol,
            endCol = endCol,
            startRow = fogStartRow,
            endRow = fogEndRow,
            offsetX = S.playCameraX,
            offsetY = S.playCameraY,
            zoomLevel = 1.0,
            mapX = 0,
            mapY = 0,
        })

        if playerLightIdx then
            table.remove(sources, playerLightIdx)
        end

        M._fogOfWar.DrawLanterns(vg, {
            gridSize = C.GRID,
            offsetX = S.playCameraX,
            offsetY = S.playCameraY,
            zoomLevel = 1.0,
            mapX = 0,
            mapY = 0,
        })

        M._fogOfWar.DrawUnlitLanterns(vg, {
            gridSize = C.GRID,
            offsetX = S.playCameraX,
            offsetY = S.playCameraY,
            zoomLevel = 1.0,
            mapX = 0,
            mapY = 0,
        })
    end

    function M.DrawHUD(vg)
        local zoom = S.playerParams.cameraZoom or 1.0
        local hudW = S.playViewW * zoom
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, hudW, 22)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        nvgFill(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        local flamePercent = math.floor(S.playAlivePixels / math.max(1, S.playTotalPixels) * 100)
        local flameG = math.floor(200 * (flamePercent / 100))
        nvgFillColor(vg, nvgRGBA(255, flameG, 30, 255))
        nvgText(vg, 6, 11, "FLAME:" .. flamePercent .. "%")

        nvgFillColor(vg, nvgRGBA(150, 255, 150, 255))
        nvgText(vg, 100, 11, "JUMP:" .. M.CalcJump() .. "G")

        M.DrawBackButton(vg)
        M.DrawWorldPlayFileName(vg)
    end

    function M.DrawBackButton(vg)
        local zoom = S.playerParams.cameraZoom or 1.0
        local hudW = S.playViewW * zoom
        local isWorldPlay = (S.editorMode == C.MODE_WORLDPLAY)
        local backBtnLabel = isWorldPlay and "返回世界" or "返回编辑"
        local backBtnW = isWorldPlay and 60 or 50
        local backBtnH = 16
        local backBtnX = hudW - backBtnW - 6
        local backBtnY = (22 - backBtnH) * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, backBtnX, backBtnY, backBtnW, backBtnH, 3)
        nvgFillColor(vg, nvgRGBA(80, 60, 40, 230))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, backBtnX, backBtnY, backBtnW, backBtnH, 3)
        nvgStrokeColor(vg, nvgRGBA(255, 180, 80, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 150, 255))
        nvgText(vg, backBtnX + backBtnW * 0.5, backBtnY + backBtnH * 0.5, backBtnLabel)
    end

    function M.DrawWorldPlayFileName(vg)
        if S.editorMode ~= C.MODE_WORLDPLAY or not S.worldPlayCurrentFile then return end
        local zoom = S.playerParams.cameraZoom or 1.0
        local hudW = S.playViewW * zoom
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, 200))
        nvgText(vg, hudW * 0.5, 3, S.worldPlayCurrentFile)
    end

    function M.DrawOverlays(vg)
        local isWorldPlay = (S.editorMode == C.MODE_WORLDPLAY)
        local escHint = isWorldPlay and "ESC:WORLD" or "ESC:EDIT"

        if not S.play.alive then
            M.DrawDeathOverlay(vg, escHint)
        elseif S.play.won then
            M.DrawWinOverlay(vg, escHint)
        end

        M.DrawBonfireMessage(vg)
    end

    function M.DrawDeathOverlay(vg, escHint)
        local zoom = S.playerParams.cameraZoom or 1.0
        local w = S.playViewW * zoom
        local h = S.playViewH * zoom
        local centerX = w * 0.5
        local centerY = h * 0.5
        local maxRadius = math.sqrt(w * w + h * h) * 0.5

        local phase = M.deathPhase
        if phase == "circleClose" then
            local progress = math.min(M.deathPhaseTimer / 0.6, 1.0)
            local radius = maxRadius * (1.0 - progress)
            nvgPathWinding(vg, NVG_SOLID)
            nvgBeginPath(vg)
            nvgRect(vg, -100, -100, w + 200, h + 200)
            if radius > 0.5 then
                nvgCircle(vg, centerX, centerY, radius)
                nvgPathWinding(vg, NVG_HOLE)
            end
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            nvgFill(vg)

        elseif phase == "blackout" then
            nvgBeginPath(vg)
            nvgRect(vg, -100, -100, w + 200, h + 200)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            nvgFill(vg)

        elseif phase == "waitKey" then
            nvgBeginPath(vg)
            nvgRect(vg, -100, -100, w + 200, h + 200)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
            nvgFill(vg)

            local pixSize = 3.0 * zoom
            M.DrawPixelText(vg, "YOU DIE", centerX, centerY - 10 * zoom, pixSize, 255, 60, 60, 255)

            local blink = math.floor(M.deathPhaseTimer * 3) % 2
            if blink == 0 then
                local hintPixSize = 1.5 * zoom
                M.DrawPixelText(vg, "PRESS ANY KEY", centerX, centerY + 20 * zoom, hintPixSize, 255, 255, 255, 200)
            end

            local escPixSize = 1.2 * zoom
            M.DrawPixelText(vg, escHint, centerX, centerY + 38 * zoom, escPixSize, 180, 180, 180, 180)

        else
            local progress = math.min(S.play.deathTimer / 0.1, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, -100, -100, w + 200, h + 200)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(255 * progress)))
            nvgFill(vg)
        end
    end

    function M.DrawBonfireMessage(vg)
        if not M.bonfireMsg.active then return end
        local zoom = S.playerParams.cameraZoom or 1.0
        local w = S.playViewW * zoom
        local h = S.playViewH * zoom
        local t = M.bonfireMsg.timer
        local dur = M.bonfireMsg.duration
        local alpha = 255
        if t < 0.3 then
            alpha = math.floor(255 * t / 0.3)
        elseif t > dur - 0.3 then
            alpha = math.floor(255 * (dur - t) / 0.3)
        end
        local pixSize = 2.5 * zoom
        M.DrawPixelText(vg, "BONFIRE LIT", w * 0.5, h * 0.4, pixSize, 255, 180, 50, alpha)
    end

    function M.DrawWinOverlay(vg, escHint)
        local zoom = S.playerParams.cameraZoom or 1.0
        local w = S.playViewW * zoom
        local h = S.playViewH * zoom
        nvgBeginPath(vg)
        nvgRect(vg, -100, -100, w + 200, h + 200)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
        nvgFill(vg)
        local pixSize = 2.5 * zoom
        M.DrawPixelText(vg, "FLAME ETERNAL", w * 0.5, h * 0.4, pixSize, 255, 200, 50, 255)
        local escPixSize = 1.2 * zoom
        M.DrawPixelText(vg, escHint, w * 0.5, h * 0.55, escPixSize, 255, 255, 255, 200)
    end

    function M.DrawCheckpointTile(vg, px, py, row, col)
        local key = row .. "_" .. col
        local activated = S.checkpointActivated[key]
        local ps = 5

        local drawBaseY = py + C.GRID
        local drawTopY = drawBaseY - 10 * ps
        local drawLeftX = px + (C.GRID - 10 * ps) * 0.5
        local t = S.flameTime or 0

        local stones = {
            {1,8},{2,8},{3,8},{4,8},{5,8},{6,8},{7,8},{8,8},
            {0,9},{1,9},{2,9},{3,9},{4,9},{5,9},{6,9},{7,9},{8,9},{9,9},
        }
        for _, s in ipairs(stones) do
            local sx = drawLeftX + s[1] * ps
            local sy = drawTopY + s[2] * ps
            nvgBeginPath(vg)
            nvgRect(vg, sx, sy, ps, ps)
            if s[2] == 9 then
                nvgFillColor(vg, nvgRGBA(40, 38, 35, 255))
            else
                nvgFillColor(vg, nvgRGBA(65, 60, 52, 255))
            end
            nvgFill(vg)
        end

        local logs = {
            {2,7},{3,7},{4,7},{5,7},{6,7},{7,7},
            {1,6},{2,6},{3,6},{4,6},{5,6},{6,6},{7,6},{8,6},
            {2,5},{3,5},{4,5},{5,5},{6,5},{7,5},
        }

        local emberFlick = math.sin(t * 3.5 + col * 1.3) * 0.3 + 0.7
        for _, l in ipairs(logs) do
            local lx = drawLeftX + l[1] * ps
            local ly = drawTopY + l[2] * ps
            nvgBeginPath(vg)
            nvgRect(vg, lx, ly, ps, ps)
            local baseR, baseG, baseB = 80, 45, 18
            local cx = math.abs(l[1] - 4.5)
            local cy = math.abs(l[2] - 6)
            local redIntensity = math.max(0, 1.0 - (cx + cy) * 0.3) * emberFlick
            local r = math.floor(baseR + 120 * redIntensity)
            local g = math.floor(baseG + 20 * redIntensity)
            local b = math.floor(baseB + 5 * redIntensity)
            nvgFillColor(vg, nvgRGBA(r, g, b, 255))
            nvgFill(vg)
        end

        local glowPixels = {
            {3,6},{5,6},{7,6},
            {4,5},{6,5},
            {3,7},{6,7},
        }
        local glowFlick = math.sin(t * 4.5 + col * 2.7) * 0.4 + 0.6
        for _, g in ipairs(glowPixels) do
            local gx = drawLeftX + g[1] * ps
            local gy = drawTopY + g[2] * ps
            nvgBeginPath(vg)
            nvgRect(vg, gx, gy, ps, ps)
            local ga = math.floor(140 * glowFlick)
            nvgFillColor(vg, nvgRGBA(255, 60, 10, ga))
            nvgFill(vg)
        end

        nvgBeginPath(vg)
        nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 6 * ps, 8 * ps * 0.4)
        local baseGlowA = math.floor(20 + 15 * glowFlick)
        nvgFillColor(vg, nvgRGBA(200, 50, 10, baseGlowA))
        nvgFill(vg)

        if activated then
            local flicker1 = math.sin(t * 8 + col * 2.1) * 0.5 + 0.5
            local flicker2 = math.sin(t * 11 + row * 1.7) * 0.5 + 0.5
            local flicker3 = math.sin(t * 6.5 + col * 3.3) * 0.5 + 0.5

            local flames = {
                {1,4,{220,50,5}}, {2,4,{255,70,10}}, {3,4,{255,90,15}},
                {6,4,{255,80,10}}, {7,4,{255,70,10}}, {8,4,{220,50,5}},
                {1,3,{255,80,10}}, {2,3,{255,110,20}}, {3,3,{255,130,25}},
                {6,3,{255,120,20}}, {7,3,{255,100,15}}, {8,3,{255,70,10}},
                {4,3,{255,160,40}}, {5,3,{255,150,35}},
                {3,2,{255,170,50}}, {4,2,{255,200,60}}, {5,2,{255,190,55}}, {6,2,{255,170,50}},
                {2,2,{255,130,25}}, {7,2,{255,130,25}},
                {3,1,{255,200,60}}, {4,1,{255,230,90}}, {5,1,{255,220,80}}, {6,1,{255,200,60}},
                {4,0,{255,245,130}}, {5,0,{255,240,110}},
                {3,0,{255,200,60}}, {6,0,{255,200,60}},
            }
            for _, f in ipairs(flames) do
                local fx = drawLeftX + f[1] * ps
                local fy = drawTopY + f[2] * ps
                local c = f[3]
                local flick
                if f[2] <= 1 then flick = flicker1
                elseif f[2] <= 2 then flick = flicker2
                else flick = flicker3 end
                local a = math.floor(200 + 55 * flick)
                nvgBeginPath(vg)
                nvgRect(vg, fx, fy, ps, ps)
                nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], a))
                nvgFill(vg)
            end

            local glowA1 = math.floor(35 + 25 * flicker1)
            nvgBeginPath(vg)
            nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 2 * ps, 18)
            nvgFillColor(vg, nvgRGBA(255, 150, 30, glowA1))
            nvgFill(vg)
            local glowA2 = math.floor(15 + 10 * flicker2)
            nvgBeginPath(vg)
            nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 2 * ps, 28)
            nvgFillColor(vg, nvgRGBA(255, 100, 10, glowA2))
            nvgFill(vg)

            M.SpawnFlameParticles(key)
        else
            local embers = {
                {3,4},{4,4},{5,4},{6,4},
                {4,3},{5,3},
            }
            local eFlick = math.sin(t * 3 + col) * 0.3 + 0.7
            for _, e in ipairs(embers) do
                local ex = drawLeftX + e[1] * ps
                local ey = drawTopY + e[2] * ps
                nvgBeginPath(vg)
                nvgRect(vg, ex, ey, ps, ps)
                local ea = math.floor(100 + 55 * eFlick)
                nvgFillColor(vg, nvgRGBA(160, 50, 10, ea))
                nvgFill(vg)
            end

            M.SpawnEmberParticles(key)
        end

        local particles = M.campfireParticles[key]
        if particles and #particles > 0 then
            local centerX = drawLeftX + 5 * ps
            local centerY = drawTopY + 4 * ps
            for _, p in ipairs(particles) do
                local alpha = math.floor(255 * (p.life / p.maxLife))
                nvgBeginPath(vg)
                nvgRect(vg, centerX + p.x, centerY + p.y, p.size, p.size)
                nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, alpha))
                nvgFill(vg)
            end
        end

        local ignite = M.campfireIgniteEffect[key]
        if ignite then
            local progress = ignite.timer / ignite.duration
            if progress < 0.15 then
                local flashA = math.floor(180 * (1.0 - progress / 0.15))
                nvgBeginPath(vg)
                nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 4 * ps, 30 + 20 * (progress / 0.15))
                nvgFillColor(vg, nvgRGBA(255, 220, 100, flashA))
                nvgFill(vg)
            end
            if progress > 0.05 and progress < 0.6 then
                local ringProgress = (progress - 0.05) / 0.55
                local ringR = 10 + 35 * ringProgress
                local ringA = math.floor(200 * (1.0 - ringProgress))
                nvgBeginPath(vg)
                nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 4 * ps, ringR)
                nvgStrokeColor(vg, nvgRGBA(255, 100, 20, ringA))
                nvgStrokeWidth(vg, 3.0 - 2.0 * ringProgress)
                nvgStroke(vg)
            end
            if progress < 0.4 then
                local pulseA = math.floor(120 * (1.0 - progress / 0.4))
                nvgBeginPath(vg)
                nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 5 * ps, 25)
                nvgFillColor(vg, nvgRGBA(255, 120, 20, pulseA))
                nvgFill(vg)
            end
        end
    end

    function M.DrawPipeTile(vg, px, py, row, col)
        if col > 1 then
            local leftVal = S.levelData[row][col - 1]
            if TileUtils.GetTileType(leftVal) == C.TILE.PIPE then return end
        end
        if row > 1 then
            local topVal = S.levelData[row - 1][col]
            if TileUtils.GetTileType(topVal) == C.TILE.PIPE then return end
        end
        local val = S.levelData[row][col]
        local switchGroup, waterTypeIndex = TileUtils.ParsePipeValue(val)
        local pipe = { switchGroup = switchGroup, waterTypeIndex = waterTypeIndex, col = col, row = row }
        PipeSystem.DrawPipe(vg, px, py, pipe)
    end

    function M.DrawFragileTile(vg, px, py, row, col)
        local key = row .. "_" .. col
        if S.play.fragileGone[key] then return end

        local G = C.GRID
        local onIt = false
        if S.play.fragilePrevPlatform and S.play.fragilePrevPlatform[key] then
            onIt = true
        end

        local r1 = onIt and 55 or 75
        local g1 = onIt and 38 or 60
        local b1 = onIt and 28 or 45
        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + 0.5, G - 1, G - 1)
        nvgFillColor(vg, nvgRGBA(r1, g1, b1, 255))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + 0.5, G - 1, 1)
        nvgFillColor(vg, nvgRGBA(110, 90, 65, 180))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRect(vg, px + 0.5, py + G - 2, G - 1, 1.5)
        nvgFillColor(vg, nvgRGBA(30, 20, 12, 180))
        nvgFill(vg)

        local cx = px + G * 0.5
        local cy = py + G * 0.5
        nvgStrokeColor(vg, nvgRGBA(30, 20, 10, 190))
        nvgStrokeWidth(vg, 0.8)
        nvgBeginPath(vg)
        nvgMoveTo(vg, px + 2, py + 3)
        nvgLineTo(vg, cx - 1, cy - 2)
        nvgLineTo(vg, cx + 2, cy + 1)
        nvgLineTo(vg, px + G - 3, py + G - 2)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - 1, cy - 2)
        nvgLineTo(vg, cx + 3, cy - 4)
        nvgStroke(vg)

        nvgBeginPath(vg)
        nvgMoveTo(vg, px + G - 4, py + 0.5)
        nvgLineTo(vg, px + G - 1, py + 0.5)
        nvgLineTo(vg, px + G - 1, py + 3)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(20, 15, 10, 200))
        nvgFill(vg)

        if onIt then
            nvgStrokeColor(vg, nvgRGBA(180, 50, 20, 220))
            nvgStrokeWidth(vg, 1.0)
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx, cy)
            nvgLineTo(vg, px + 1, cy - 3)
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx, cy)
            nvgLineTo(vg, px + G - 2, cy + 2)
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx, cy)
            nvgLineTo(vg, cx + 1, py + G - 1)
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx, cy)
            nvgLineTo(vg, cx - 2, py + 1)
            nvgStroke(vg)
        end
    end

    function M.DrawDecorations(vg, startCol, endCol)
        if #S.decorations == 0 then return end

        local zoom = S.playerParams.cameraZoom or 1.0
        local visibleH = S.playViewH * zoom
        local startRow = math.max(1, math.floor(S.playCameraY / C.GRID) + 1)
        local endRow = math.min(S.MAP_ROWS, startRow + math.ceil(visibleH / C.GRID) + 2)

        for _, deco in ipairs(S.decorations) do
            if deco.col >= startCol and deco.col <= endCol and deco.row >= startRow and deco.row <= endRow then
                local decoType = C.DECORATION_TYPES[deco.typeId]
                if not decoType then goto continuePlay end

                local px = (deco.col - 1) * C.GRID - S.playCameraX
                local py = (deco.row - 1) * C.GRID - S.playCameraY

                if decoType.sprite and decoType.size then
                    local sizeW = decoType.size.w or 1
                    local sizeH = decoType.size.h or 1
                    local scaleFactor = (deco.scale or 100) / 100
                    local drawW = sizeW * C.GRID * scaleFactor
                    local drawH = sizeH * C.GRID * scaleFactor
                    local imgX = px + C.GRID * 0.5 - drawW * 0.5
                    local imgY = py + C.GRID * 0.5 - drawH * 0.5

                    if not playDecoImageCache[decoType.sprite] then
                        local handle = nvgCreateImage(vg, decoType.sprite, 0)
                        playDecoImageCache[decoType.sprite] = handle or -1
                    end

                    local imgHandle = playDecoImageCache[decoType.sprite]
                    if imgHandle and imgHandle > 0 then
                        local paint = nvgImagePattern(vg, imgX, imgY, drawW, drawH, 0, imgHandle, 1.0)
                        nvgBeginPath(vg)
                        nvgRect(vg, imgX, imgY, drawW, drawH)
                        nvgFillPaint(vg, paint)
                        nvgFill(vg)
                    end
                else
                    local color = decoType.color or {180, 140, 220}
                    nvgBeginPath(vg)
                    nvgRect(vg, px, py, C.GRID, C.GRID)
                    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 150))
                    nvgFill(vg)
                end

                ::continuePlay::
            end
        end
    end

end

return Renderer
