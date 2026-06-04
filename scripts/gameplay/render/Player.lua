------------------------------------------------------------
-- gameplay/render/Player.lua — 玩家渲染（火球、玩家像素、下落粒子）
------------------------------------------------------------
local Config = require("gameplay.Config")

local Player = {}

function Player.Attach(M)
    -- ====================================================================
    -- 火球渲染（飞行中+尾迹+吸收动画）
    -- ====================================================================
    function M.DrawFireball()
        local vg = M.vg
        local Fireball = require("gameplay.Fireball")
        local PlayerController = M._PlayerController
        local Physics = M._Physics
        local t = M.gameTime

        -- 渲染吸收动画
        local absorbAnim = Fireball.GetAbsorbAnim()
        if absorbAnim then
            local progress = absorbAnim.timer / absorbAnim.duration
            -- 粒子收缩到玩家中心
            local player = PlayerController.player
            local s = Physics.PlayerGridSize()
            local playerCX = (player.gridX - 1) * Config.GRID + s * Config.GRID * 0.5
            local playerCY = (player.gridY - 1) * Config.GRID + s * Config.GRID * 0.5
            -- 生成 6 个粒子从能力点向玩家飞
            for i = 1, 6 do
                local angle = (i / 6) * math.pi * 2 + t * 3
                local startRadius = 12 * (1 - progress)
                local sx = absorbAnim.x + math.cos(angle) * startRadius
                local sy = absorbAnim.y + math.sin(angle) * startRadius
                local fx = sx + (playerCX - sx) * progress
                local fy = sy + (playerCY - sy) * progress
                local alpha = math.floor(255 * (1 - progress))
                local size = 2 * (1 - progress * 0.5)
                nvgBeginPath(vg)
                nvgCircle(vg, fx - M.cameraX, fy, size)
                nvgFillColor(vg, nvgRGBA(200, 120, 255, alpha))
                nvgFill(vg)
            end
        end

        -- 渲染火球
        local fb = Fireball.GetFireball()
        if not fb then return end

        local fbX = fb.x - M.cameraX
        local fbY = fb.y

        -- 绘制尾迹（使用相对偏移，避免相机移动造成曲线错觉）
        for i, trail in ipairs(fb.trail) do
            if trail.alpha > 0 then
                local tAlpha = math.floor(trail.alpha * 180)
                local tSize = 3 - i * 0.3
                if tSize > 0 then
                    nvgBeginPath(vg)
                    nvgCircle(vg, fbX + trail.offX, fbY + trail.offY, tSize)
                    nvgFillColor(vg, nvgRGBA(255, 160, 40, tAlpha))
                    nvgFill(vg)
                end
            end
        end

        -- 绘制火球本体（带闪烁）
        local flick = math.sin(t * 20) * 0.2 + 0.8
        -- 外圈光晕
        nvgBeginPath(vg)
        nvgCircle(vg, fbX, fbY, 6 * flick)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, 60))
        nvgFill(vg)
        -- 中心球
        nvgBeginPath(vg)
        nvgCircle(vg, fbX, fbY, 4)
        nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
        nvgFill(vg)
        -- 核心亮点（偏向飞行反方向）
        nvgBeginPath(vg)
        nvgCircle(vg, fbX - fb.dx * 1.5, fbY - fb.dy * 1.5, 2)
        nvgFillColor(vg, nvgRGBA(255, 255, 220, 255))
        nvgFill(vg)
    end

    -- ====================================================================
    -- 火焰玩家渲染
    -- ====================================================================
    function M.DrawPlayer()
        local vg = M.vg
        local PlayerController = M._PlayerController
        local PixelSystem = M._PixelSystem
        local Animation = M._Animation
        local player = PlayerController.player
        local GRID = Config.GRID
        local PC = Config.PLAYER_CONFIG
        local ps = PC.pixelSize
        local N = PC.pixelGridSize
        local totalSize = N * ps

        local baseX = (player.gridX - 1) * GRID - M.cameraX
        local baseY = (player.gridY - 1) * GRID

        -- 跳不动抖动偏移
        local shakeX, shakeY = Animation.GetCantJumpShakeOffset()
        baseX = baseX + shakeX * ps
        baseY = baseY + shakeY * ps

        local pivotX = baseX + totalSize * 0.5
        local pivotY = baseY + totalSize

        -- 主角光源
        local flameRatio = PixelSystem.alivePixels / math.max(1, PixelSystem.totalPixels)
        local lightDiameter = PC.defaultLightDiameter * GRID * flameRatio
        local lightRadius = lightDiameter * 0.5
        if lightRadius > 0 then
            local lightCX = pivotX
            local lightCY = baseY + totalSize * 0.5
            local lightAlphaBase = math.floor(30 + 10 * math.sin(M.gameTime * PC.flickerSpeed * 0.7))
            local outerGlow = nvgRadialGradient(vg, lightCX, lightCY, lightRadius * 0.2, lightRadius,
                nvgRGBA(255, 150, 40, lightAlphaBase),
                nvgRGBA(255, 80, 0, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, lightCX, lightCY, lightRadius)
            nvgFillPaint(vg, outerGlow)
            nvgFill(vg)
        end

        -- 近距光晕
        local glowRadius = totalSize * 0.6 * flameRatio
        local glowAlpha = math.floor(40 + 20 * math.sin(M.gameTime * PC.flickerSpeed))
        nvgBeginPath(vg)
        nvgCircle(vg, pivotX, pivotY - totalSize * 0.5, glowRadius)
        nvgFillColor(vg, nvgRGBA(255, 120, 0, glowAlpha))
        nvgFill(vg)

        local brightFrame = Animation.flameAnimFrame

        -- 预计算行宽度
        local rowWidth = {}
        for row = 1, N do
            local minCol, maxCol = N + 1, 0
            for col = 1, N do
                if PixelSystem.pixelState[row][col] then
                    if col < minCol then minCol = col end
                    if col > maxCol then maxCol = col end
                end
            end
            rowWidth[row] = (maxCol >= minCol) and (maxCol - minCol + 1) or 0
        end

        -- 合并水平偏移
        local combinedH = {}
        for row = 1, N do
            local raw = (Animation.rowOffsets[row] or 0) + (Animation.lanternRowShifts[row] or 0)
            local w = rowWidth[row]
            local maxShift
            if w <= 2 then maxShift = 0
            elseif w <= 4 then maxShift = 1
            else maxShift = math.max(1, math.floor(w * 0.3)) end
            combinedH[row] = math.max(-maxShift, math.min(maxShift, raw))
        end

        combinedH[N] = 0
        combinedH[N - 1] = 0
        for row = N - 2, 1, -1 do
            local diff = combinedH[row] - combinedH[row + 1]
            if diff > 1 then combinedH[row] = combinedH[row + 1] + 1
            elseif diff < -1 then combinedH[row] = combinedH[row + 1] - 1 end
        end
        for row = 2, N do
            local diff = combinedH[row] - combinedH[row - 1]
            if diff > 1 then combinedH[row] = combinedH[row - 1] + 1
            elseif diff < -1 then combinedH[row] = combinedH[row - 1] - 1 end
        end
        for row = N - 2, 1, -1 do
            local diff = combinedH[row] - combinedH[row + 1]
            if diff > 1 then combinedH[row] = combinedH[row + 1] + 1
            elseif diff < -1 then combinedH[row] = combinedH[row + 1] - 1 end
        end

        -- 绘制像素
        for row = 1, N do
            local hShift = combinedH[row]
            for col = 1, N do
                if PixelSystem.pixelState[row][col] then
                    local squashShift, squashSkip = Animation.GetJumpSquashForPixel(row, col)
                    if not squashSkip then
                        local baseColor = Config.FLAME_COLORS[row]
                        local flickSeed = (brightFrame * 3 + row * 7 + col * 13) % 10
                        local brightness
                        if flickSeed < 2 then brightness = 1.25
                        elseif flickSeed < 5 then brightness = 1.0
                        else brightness = 0.85 end
                        if row <= 2 then brightness = brightness + 0.15 end
                        local cx = (N + 1) / 2
                        if math.abs(col - cx) >= 3 then brightness = brightness * 0.85 end

                        local r = math.min(255, math.max(0, math.floor(baseColor[1] * brightness)))
                        local g = math.min(255, math.max(0, math.floor(baseColor[2] * brightness)))
                        local b = math.min(255, math.max(0, math.floor(baseColor[3] * brightness)))

                        local drawCol = col
                        if not player.facingRight then drawCol = N - col + 1 end
                        local ppx = baseX + (drawCol - 1 + hShift + squashShift) * ps
                        local ppy = baseY + (row - 1) * ps

                        nvgBeginPath(vg)
                        nvgRect(vg, ppx, ppy, ps, ps)
                        nvgFillColor(vg, nvgRGBA(r, g, b, 255))
                        nvgFill(vg)
                    end
                end
            end
        end

        -- 恢复动画闪光叠加
        local flashIntensity = M.GetRecoverFlashIntensity()
        if flashIntensity > 0 then
            local flashAlpha = math.floor(flashIntensity * 180)
            -- 给新恢复的像素一层暖黄色闪光
            for row = 1, N do
                for col = 1, N do
                    if PixelSystem.pixelState[row][col] then
                        -- 边缘像素更亮（刚恢复的通常在边缘）
                        local cx = (N + 1) / 2
                        local hDist = math.abs(col - cx)
                        local edgeFactor = hDist / (N * 0.5)
                        local pixFlash = math.floor(flashAlpha * (0.3 + edgeFactor * 0.7))
                        if pixFlash > 10 then
                            local drawCol = col
                            if not player.facingRight then drawCol = N - col + 1 end
                            local ppx = baseX + (drawCol - 1) * ps
                            local ppy = baseY + (row - 1) * ps
                            nvgBeginPath(vg)
                            nvgRect(vg, ppx, ppy, ps, ps)
                            nvgFillColor(vg, nvgRGBA(255, 240, 150, pixFlash))
                            nvgFill(vg)
                        end
                    end
                end
            end
        end

        -- 火星粒子
        if PixelSystem.alivePixels > PixelSystem.totalPixels * 0.2 then
            for i = 1, 4 do
                local life = (Animation.flameAnimFrame + i * 3) % 8
                local progress = life / 7
                local emitCol = math.floor(N * 0.3 + (i * 2.7 + Animation.flameAnimFrame * 0.3) % (N * 0.4))
                local emitX = baseX + emitCol * ps
                local emitY = baseY - life * ps
                local sparkAlpha = math.floor((1.0 - progress) * 240)
                if sparkAlpha > 20 and life > 0 then
                    local pr = 255
                    local pg = math.floor(200 * (1.0 - progress * 0.6))
                    local pb = math.floor(40 * (1.0 - progress))
                    nvgBeginPath(vg)
                    nvgRect(vg, emitX, emitY, ps, ps)
                    nvgFillColor(vg, nvgRGBA(pr, pg, pb, sparkAlpha))
                    nvgFill(vg)
                end
            end
        end

        -- 下落粒子
        M.DrawFallParticles()
    end

    -- ====================================================================
    -- 下落粒子渲染
    -- ====================================================================
    function M.DrawFallParticles()
        local vg = M.vg
        local Animation = M._Animation
        local ps = Config.PLAYER_CONFIG.pixelSize
        for _, p in ipairs(Animation.fallParticles) do
            local lifeRatio = p.life / p.maxLife
            local alpha = math.floor(lifeRatio * 255)
            local c = Config.FLAME_COLORS[p.colorRow] or Config.FLAME_COLORS[8]
            local bright = 0.5 + lifeRatio * 0.5
            local r = math.floor(c[1] * bright)
            local g = math.floor(c[2] * bright)
            local b = math.floor(c[3] * bright)

            local screenX = p.x - M.cameraX
            local drawX = math.floor(screenX / ps + 0.5) * ps
            local drawY = math.floor(p.y / ps + 0.5) * ps

            nvgBeginPath(vg)
            nvgRect(vg, drawX, drawY, p.size, p.size)
            nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
            nvgFill(vg)

            if lifeRatio > 0.3 then
                local tailX = drawX - math.floor(p.vx * 0.02 / ps + 0.5) * ps
                local tailY = drawY - math.floor(p.vy * 0.02 / ps + 0.5) * ps
                nvgBeginPath(vg)
                nvgRect(vg, tailX, tailY, p.size, p.size)
                nvgFillColor(vg, nvgRGBA(r, g, b, math.floor(alpha * 0.4)))
                nvgFill(vg)
            end
        end
    end
end

return Player
