------------------------------------------------------------
-- gameplay/Renderer.lua — 渲染系统（背景、网格、地图、角色、HUD）
------------------------------------------------------------
local Config = require("gameplay.Config")
local GAME_VERSION = require("version")

local M = {}

-- 依赖
local Physics = nil
local PixelSystem = nil
local PlayerController = nil
local LevelManager = nil
local Animation = nil

function M.Inject(deps)
    Physics = deps.Physics
    PixelSystem = deps.PixelSystem
    PlayerController = deps.PlayerController
    LevelManager = deps.LevelManager
    Animation = deps.Animation
end

-- 外部引用
M.vg = nil
M.screenDesignW = 0
M.screenDesignH = 0
M.cameraX = 0
M.gameTime = 0
M.gameState = Config.STATE_PLAYING

--- 设置渲染上下文
function M.SetContext(ctx)
    M.vg = ctx.vg
    M.screenDesignW = ctx.screenDesignW
    M.screenDesignH = ctx.screenDesignH
    M.cameraX = ctx.cameraX
    M.gameTime = ctx.gameTime
    M.gameState = ctx.gameState
end

-- ====================================================================
-- 背景
-- ====================================================================
function M.DrawBackground()
    local vg = M.vg
    local bg = nvgLinearGradient(vg, 0, 0, 0, M.screenDesignH,
        nvgRGBA(10, 5, 20, 255), nvgRGBA(30, 15, 40, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, M.screenDesignW, M.screenDesignH)
    nvgFillPaint(vg, bg)
    nvgFill(vg)
end

-- ====================================================================
-- 网格
-- ====================================================================
function M.DrawGrid()
    local vg = M.vg
    local GRID = Config.GRID
    local startCol = math.max(1, math.floor(M.cameraX / GRID) + 1)
    local visW = Config.DESIGN_W * (Config.PLAYER_CONFIG.cameraZoom or 1.0)
    local endCol = math.min(Config.MAP_COLS, startCol + math.ceil(visW / GRID) + 2)

    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        local x = (col - 1) * GRID - M.cameraX
        nvgMoveTo(vg, x, 0)
        nvgLineTo(vg, x, Config.MAP_ROWS * GRID)
    end
    for row = 1, Config.MAP_ROWS + 1 do
        local y = (row - 1) * GRID
        local x0 = (startCol - 1) * GRID - M.cameraX
        local x1 = (endCol) * GRID - M.cameraX
        nvgMoveTo(vg, x0, y)
        nvgLineTo(vg, x1, y)
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 15))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        if (col - 1) % 5 == 0 then
            local x = (col - 1) * GRID - M.cameraX
            nvgMoveTo(vg, x, 0)
            nvgLineTo(vg, x, Config.MAP_ROWS * GRID)
        end
    end
    for row = 1, Config.MAP_ROWS + 1 do
        if (row - 1) % 5 == 0 then
            local y = (row - 1) * GRID
            local x0 = (startCol - 1) * GRID - M.cameraX
            local x1 = (endCol) * GRID - M.cameraX
            nvgMoveTo(vg, x0, y)
            nvgLineTo(vg, x1, y)
        end
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 35))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

-- ====================================================================
-- 地图
-- ====================================================================
function M.DrawMap()
    local vg = M.vg
    local GRID = Config.GRID
    local TILE = LevelManager.TILE
    local startCol = math.max(1, math.floor(M.cameraX / GRID) + 1)
    local visW = Config.DESIGN_W * (Config.PLAYER_CONFIG.cameraZoom or 1.0)
    local endCol = math.min(Config.MAP_COLS, startCol + math.ceil(visW / GRID) + 2)

    for row = 1, Config.MAP_ROWS do
        for col = startCol, endCol do
            local val = LevelManager.levelData[row][col]
            if val == TILE.EMPTY then goto continueTile end

            local base, group = Physics.GetTileType(val)
            local px = (col - 1) * GRID - M.cameraX
            local py = (row - 1) * GRID

            if base == TILE.SOLID then
                nvgBeginPath(vg)
                nvgRect(vg, px + 0.5, py + 0.5, GRID - 1, GRID - 1)
                nvgFillColor(vg, nvgRGBA(40, 45, 55, 255))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, px + 0.5, py + 0.5, GRID - 1, 2)
                nvgFillColor(vg, nvgRGBA(60, 70, 80, 255))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, px + 0.5, py + 0.5, 2, GRID - 1)
                nvgFillColor(vg, nvgRGBA(55, 60, 70, 255))
                nvgFill(vg)

            elseif base == TILE.SPAWN then
                nvgBeginPath(vg)
                nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 6)
                nvgFillColor(vg, nvgRGBA(255, 200, 50, 40))
                nvgFill(vg)

            elseif base == TILE.FUEL then
                local key = row .. "_" .. col
                if not LevelManager.collectedItems[key] then
                    local flicker = math.sin(M.gameTime * 6 + col * 1.7) * 0.3 + 0.7
                    local r = math.floor(255 * flicker)
                    local g = math.floor(120 * flicker)
                    nvgBeginPath(vg)
                    nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 7)
                    nvgFillColor(vg, nvgRGBA(255, 100, 0, math.floor(60 * flicker)))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 4)
                    nvgFillColor(vg, nvgRGBA(r, g, 10, 255))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5 - 1, 2)
                    nvgFillColor(vg, nvgRGBA(255, 255, 200, math.floor(200 * flicker)))
                    nvgFill(vg)
                end

            elseif base == TILE.GOAL then
                nvgBeginPath(vg)
                nvgRect(vg, px + 2, py, GRID - 4, GRID)
                nvgFillColor(vg, nvgRGBA(100, 255, 100, 60))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, px + 2, py, 2, GRID)
                nvgFillColor(vg, nvgRGBA(100, 255, 100, 220))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, px + GRID - 4, py, 2, GRID)
                nvgFillColor(vg, nvgRGBA(100, 255, 100, 220))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, px + 2, py, GRID - 4, 2)
                nvgFillColor(vg, nvgRGBA(100, 255, 100, 220))
                nvgFill(vg)
                local glow = math.sin(M.gameTime * 3) * 0.3 + 0.7
                nvgBeginPath(vg)
                nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 8)
                nvgFillColor(vg, nvgRGBA(100, 255, 100, math.floor(30 * glow)))
                nvgFill(vg)

            elseif base == TILE.SPIKE then
                nvgBeginPath(vg)
                nvgMoveTo(vg, px + 2, py + GRID - 2)
                nvgLineTo(vg, px + GRID * 0.5, py + 2)
                nvgLineTo(vg, px + GRID - 2, py + GRID - 2)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(200, 30, 30, 255))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgMoveTo(vg, px + GRID * 0.5 - 1, py + 3)
                nvgLineTo(vg, px + GRID * 0.5, py + 2)
                nvgLineTo(vg, px + GRID * 0.5 + 1, py + 3)
                nvgStrokeColor(vg, nvgRGBA(255, 180, 180, 200))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)

            elseif base == TILE.SWITCH then
                local key = row .. "_" .. col
                local gc = Config.GROUP_COLORS[group] or Config.GROUP_COLORS[1]
                local activated = LevelManager.switchCollected[key]
                nvgBeginPath(vg)
                nvgRoundedRect(vg, px + 3, py + GRID - 5, GRID - 6, 4, 1)
                nvgFillColor(vg, nvgRGBA(80, 80, 80, 255))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 5)
                if activated then
                    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 80))
                else
                    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
                end
                nvgFill(vg)
                if not activated then
                    nvgBeginPath(vg)
                    nvgRect(vg, px + GRID * 0.5 - 1, py + 2, 2, 6)
                    nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
                    nvgFill(vg)
                end

            elseif base == TILE.GATE then
                local gc = Config.GROUP_COLORS[group] or Config.GROUP_COLORS[1]
                local open = LevelManager.switchState[group]
                if not open then
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 1, py, GRID - 2, GRID)
                    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 180))
                    nvgFill(vg)
                    for dx = 0, 2 do
                        nvgBeginPath(vg)
                        nvgRect(vg, px + 3 + dx * 5, py + 2, 2, GRID - 4)
                        nvgFillColor(vg, nvgRGBA(
                            math.floor(gc[1] * 0.3),
                            math.floor(gc[2] * 0.3),
                            math.floor(gc[3] * 0.3), 255))
                        nvgFill(vg)
                    end
                else
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 1, py, GRID - 2, GRID)
                    nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 50))
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)
                end

            elseif base == TILE.HIDDEN_WALL then
                if not LevelManager.hiddenWallRevealed[group] then
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 0.5, py + 0.5, GRID - 1, GRID - 1)
                    nvgFillColor(vg, nvgRGBA(40, 45, 55, 255))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 0.5, py + 0.5, GRID - 1, 2)
                    nvgFillColor(vg, nvgRGBA(60, 70, 80, 255))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 0.5, py + 0.5, 2, GRID - 1)
                    nvgFillColor(vg, nvgRGBA(55, 60, 70, 255))
                    nvgFill(vg)
                end
            end

            ::continueTile::
        end
    end
end

-- ====================================================================
-- 火焰玩家渲染
-- ====================================================================
function M.DrawPlayer()
    local vg = M.vg
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

-- ====================================================================
-- HUD
-- ====================================================================
function M.DrawHUD()
    local vg = M.vg
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, M.screenDesignW, 22)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    local diffNames = { easy = "Easy", normal = "Normal", hard = "Hard" }
    local diffColors = { easy = {100,220,100}, normal = {220,200,60}, hard = {255,80,60} }
    local dc = diffColors[LevelManager.currentDifficulty] or {200,200,200}
    nvgFillColor(vg, nvgRGBA(dc[1], dc[2], dc[3], 255))
    nvgText(vg, 6, 11, "Lv" .. LevelManager.levelNumber .. " " .. (diffNames[LevelManager.currentDifficulty] or "?"))

    local flamePercent = math.floor(PixelSystem.alivePixels / math.max(1, PixelSystem.totalPixels) * 100)
    local flameR = 255
    local flameG = math.floor(200 * (flamePercent / 100))
    nvgFillColor(vg, nvgRGBA(flameR, flameG, 30, 255))
    nvgText(vg, 90, 11, "FLAME:" .. flamePercent .. "%")

    nvgFillColor(vg, nvgRGBA(150, 255, 150, 255))
    nvgText(vg, 175, 11, "JUMP:" .. PlayerController.CalcJumpHeight() .. "G")

    nvgFillColor(vg, nvgRGBA(255, 140, 40, 255))
    nvgText(vg, 235, 11, "FUEL:" .. LevelManager.fuelCount)

    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFontSize(vg, 8)
    nvgFillColor(vg, nvgRGBA(100, 105, 120, 150))
    nvgText(vg, M.screenDesignW - 6, 11, "v" .. GAME_VERSION)

    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(180, 180, 180, 150))
    local versionW = nvgTextBounds(vg, 0, 0, "v" .. GAME_VERSION) + 8
    nvgText(vg, M.screenDesignW - 6 - versionW, 11, "R:Retry N:Next 1/2/3:Diff")

    if M.gameState == Config.STATE_GAMEOVER then
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(255, 60, 60, 255))
        nvgText(vg, M.screenDesignW * 0.5, M.screenDesignH * 0.4, "FLAME OUT!")
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, M.screenDesignW * 0.5, M.screenDesignH * 0.52, "R:Retry  N:New Level")
    elseif M.gameState == Config.STATE_WIN then
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
        nvgText(vg, M.screenDesignW * 0.5, M.screenDesignH * 0.4, "FLAME ETERNAL!")
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, M.screenDesignW * 0.5, M.screenDesignH * 0.52, "N:Next Level  R:Replay")
    end
end

-- ====================================================================
-- 过渡遮罩
-- ====================================================================
function M.DrawLevelTransition()
    if not LevelManager.transition.active then return end
    if LevelManager.transition.alpha <= 0 then return end
    local vg = M.vg
    local a = math.floor(LevelManager.transition.alpha * 255)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, M.screenDesignW, M.screenDesignH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, a))
    nvgFill(vg)
end

return M
