------------------------------------------------------------
-- FlameRenderer.lua — 火焰像素渲染（试玩模式）
------------------------------------------------------------
local C = require("editor.Constants")
local S = require("editor.State")

local M = {}

------------------------------------------------------------
-- 火焰动画帧（逐行偏移）
------------------------------------------------------------

function M.UpdateFlameAnim()
    local N = C.FLAME_CFG.pixelGridSize
    local t = S.flameTime
    local maxAmp, vertAmp = M.GetAmplitudes()
    local rawOffsets = M.CalcRawOffsets(N, t, maxAmp)
    M.ApplySmoothing(rawOffsets, N)
    M.ApplyVerticalOffsets(N, t, vertAmp)
end

function M.GetAmplitudes()
    local maxAmp = 1
    local vertAmp = 0
    if not S.play.isOnGround and not S.play.isJumping then
        maxAmp = 3; vertAmp = 1
    elseif S.play.isMoving then
        maxAmp = 2; vertAmp = 1
    end
    return maxAmp, vertAmp
end

function M.CalcRawOffsets(N, t, maxAmp)
    local rawOffsets = {}
    for row = 1, N do
        local rowFactor = (N - row) / (N - 1)
        local wave = math.sin(t * 4.5 - row * 0.55) * 0.55
                   + math.sin(t * 7.8 + row * 0.8 + 1.7) * 0.3
                   + math.sin(t * 12.0 - row * 1.3 + 3.1) * 0.15
        local hOffset = wave * maxAmp * rowFactor
        if S.play.isMoving then
            local leanDir = S.play.facingRight and 1 or -1
            hOffset = hOffset + rowFactor * 1.5 * leanDir
        end
        if row <= 3 then
            hOffset = hOffset + M.CalcTipOffset(t, row, maxAmp)
        end
        rawOffsets[row] = math.floor(hOffset + 0.5)
    end
    return rawOffsets
end

function M.CalcTipOffset(t, row, maxAmp)
    local tipFactor = (4 - row) / 3
    local tipWave = math.sin(t * 9.0 + row * 2.5) * 0.6
                  + math.sin(t * 6.0 - row * 1.8 + 1.0) * 0.4
    return tipWave * tipFactor * (maxAmp > 1 and 1.5 or 0.8)
end

function M.ApplySmoothing(rawOffsets, N)
    rawOffsets[N] = 0
    if N > 1 then rawOffsets[N - 1] = 0 end
    for row = N - 2, 1, -1 do
        local below = rawOffsets[row + 1]
        local cur = rawOffsets[row]
        if cur > below + 1 then rawOffsets[row] = below + 1
        elseif cur < below - 1 then rawOffsets[row] = below - 1 end
    end
    for row = 1, N do
        S.rowOffsets[row] = rawOffsets[row]
    end
end

function M.ApplyVerticalOffsets(N, t, vertAmp)
    for row = 1, N do
        if vertAmp > 0 and row <= 4 then
            local vFactor = (5 - row) / 4
            local vWave = math.sin(t * 5.5 + row * 1.5)
            if vWave > 0.4 then
                S.rowVOffsets[row] = -1 * math.floor(vFactor + 0.5)
            else
                S.rowVOffsets[row] = 0
            end
        else
            S.rowVOffsets[row] = 0
        end
    end
end

------------------------------------------------------------
-- 绘制火焰主体
------------------------------------------------------------

function M.Draw()
    local vg = S.vg
    local baseX = (S.play.gridX - 1) * C.GRID - S.playCameraX
    local baseY = (S.play.gridY - 1) * C.GRID
    local ps = C.FLAME_CFG.pixelSize
    local N = C.FLAME_CFG.pixelGridSize
    local totalSize = N * ps

    M.DrawGlow(vg, baseX, baseY, totalSize)
    M.DrawPixels(vg, baseX, baseY, ps, N)
    M.DrawTipPixels(vg, baseX, baseY, ps, N)
    M.DrawFallParticles(vg)
end

function M.DrawGlow(vg, baseX, baseY, totalSize)
    local pivotX = baseX + totalSize * 0.5
    local pivotY = baseY + totalSize
    local flameRatio = S.playAlivePixels / math.max(1, S.playTotalPixels)
    local glowRadius = totalSize * 0.6 * flameRatio
    local glowAlpha = math.floor(40 + 20 * math.sin(S.playGameTime * C.FLAME_CFG.flickerSpeed))
    nvgBeginPath(vg)
    nvgCircle(vg, pivotX, pivotY - totalSize * 0.5, glowRadius)
    nvgFillColor(vg, nvgRGBA(255, 120, 0, glowAlpha))
    nvgFill(vg)
end

function M.DrawPixels(vg, baseX, baseY, ps, N)
    local brightFrame = S.flameAnimFrame
    for row = 1, N do
        local hShift = S.rowOffsets[row] or 0
        local vShift = S.rowVOffsets[row] or 0
        for col = 1, N do
            if S.pixelState[row][col] then
                M.DrawOnePixel(vg, baseX, baseY, ps, N, row, col, hShift, vShift, brightFrame)
            end
        end
    end
end

function M.DrawOnePixel(vg, baseX, baseY, ps, N, row, col, hShift, vShift, brightFrame)
    local baseColor = C.FLAME_COLORS[row]
    local brightness = M.CalcBrightness(row, col, N, brightFrame)
    local r = math.min(255, math.max(0, math.floor(baseColor[1] * brightness)))
    local g = math.min(255, math.max(0, math.floor(baseColor[2] * brightness)))
    local b = math.min(255, math.max(0, math.floor(baseColor[3] * brightness)))
    local drawCol = col
    if not S.play.facingRight then drawCol = N - col + 1 end
    local px = baseX + (drawCol - 1 + hShift) * ps
    local py = baseY + (row - 1 + vShift) * ps
    nvgBeginPath(vg)
    nvgRect(vg, px, py, ps, ps)
    nvgFillColor(vg, nvgRGBA(r, g, b, 255))
    nvgFill(vg)
end

function M.CalcBrightness(row, col, N, brightFrame)
    local flickSeed = (brightFrame * 3 + row * 7 + col * 13) % 10
    local brightness
    if flickSeed < 2 then brightness = 1.25
    elseif flickSeed < 5 then brightness = 1.0
    else brightness = 0.85 end
    if row <= 2 then brightness = brightness + 0.15 end
    local cx = (N + 1) / 2
    if math.abs(col - cx) >= 3 then brightness = brightness * 0.85 end
    if row <= 2 then
        local tipSeed = (brightFrame * 5 + col * 11 + row * 3) % 8
        if tipSeed < 2 then brightness = brightness * 1.3
        elseif tipSeed >= 6 then brightness = brightness * 0.6 end
    end
    return brightness
end

------------------------------------------------------------
-- 尖端游离像素
------------------------------------------------------------

function M.DrawTipPixels(vg, baseX, baseY, ps, N)
    local t = S.flameTime
    for _, tp in ipairs(S.tipPixels) do
        local progress = 1.0 - tp.life / tp.maxLife
        local alpha = math.floor((1.0 - progress) * 255)
        if alpha > 20 then
            M.DrawOneTipPixel(vg, baseX, baseY, ps, N, tp, t, alpha)
        end
    end
end

function M.DrawOneTipPixel(vg, baseX, baseY, ps, N, tp, t, alpha)
    local tpColor = C.FLAME_COLORS[math.max(1, math.min(3, tp.colorRow))]
    local tpBright = 0.9 + 0.3 * math.sin(tp.phase + t * 12)
    local tr = math.min(255, math.floor(tpColor[1] * tpBright))
    local tg = math.min(255, math.floor(tpColor[2] * tpBright))
    local tb = math.min(255, math.floor(tpColor[3] * tpBright))
    local drawCol = tp.col
    if not S.play.facingRight then drawCol = N - tp.col + 1 end
    local tpx = baseX + (drawCol - 1 + (S.rowOffsets[1] or 0)) * ps + tp.offX * ps
    local tpy = baseY + (tp.row - 1 + tp.offY) * ps
    nvgBeginPath(vg)
    nvgRect(vg, tpx, tpy, ps, ps)
    nvgFillColor(vg, nvgRGBA(tr, tg, tb, alpha))
    nvgFill(vg)
end

------------------------------------------------------------
-- 下落火星粒子
------------------------------------------------------------

function M.DrawFallParticles(vg)
    for _, p in ipairs(S.playFallParticles) do
        local progress = 1.0 - p.life / p.maxLife
        local alpha = math.floor((1.0 - progress) * 255)
        if alpha > 10 then
            M.DrawOneFallParticle(vg, p, progress, alpha)
        end
    end
end

function M.DrawOneFallParticle(vg, p, progress, alpha)
    local screenX = p.x - S.playCameraX
    local screenY = p.y
    local baseColor = C.FLAME_COLORS[p.colorRow] or C.FLAME_COLORS[7]
    local r = math.min(255, math.floor(baseColor[1] * (1.0 + (1.0 - progress) * 0.2)))
    local g = math.floor(baseColor[2] * (1.0 - progress * 0.3))
    local b = math.floor(baseColor[3] * (1.0 - progress * 0.5))
    local sz = p.size * (1.0 - progress * 0.5)
    nvgBeginPath(vg)
    nvgRect(vg, screenX, screenY, sz, sz)
    nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
    nvgFill(vg)
end

return M
