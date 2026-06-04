------------------------------------------------------------
-- gameplay/render/Tiles.lua — 特殊瓦片渲染（篝火、火苗道具、能力点）
------------------------------------------------------------
local Config = require("gameplay.Config")

local Tiles = {}

function Tiles.Attach(M)
    -- ====================================================================
    -- 篝火 (CHECKPOINT) 渲染
    -- ====================================================================
    function M.DrawCheckpointTile(px, py, row, col)
        local vg = M.vg
        local GRID = Config.GRID
        local LevelManager = M._LevelManager
        local key = row .. "_" .. col
        local activated = LevelManager.checkpointActivated[key]
        local ps = 3  -- 像素块大小（原2 × 1.7 ≈ 3，放大1.7倍）
        local t = M.gameTime

        -- 篝火从格子底部向上绘制，占 10 行 × 10 列 像素格
        local drawBaseY = py + GRID
        local drawTopY = drawBaseY - 10 * ps
        local drawLeftX = px + (GRID - 10 * ps) * 0.5

        -- 石头底座（行 8-9）
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

        -- 木柴堆（行 5-7，发红光效果）
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

        -- 木柴缝隙中的红色发光像素
        local glowPixels = {
            {3,6},{5,6},{7,6},
            {4,5},{6,5},
            {3,7},{6,7},
        }
        local glowFlick = math.sin(t * 4.5 + col * 2.7) * 0.4 + 0.6
        for _, gp in ipairs(glowPixels) do
            local gx = drawLeftX + gp[1] * ps
            local gy = drawTopY + gp[2] * ps
            nvgBeginPath(vg)
            nvgRect(vg, gx, gy, ps, ps)
            local ga = math.floor(140 * glowFlick)
            nvgFillColor(vg, nvgRGBA(255, 60, 10, ga))
            nvgFill(vg)
        end

        -- 篝火底部红色光晕
        nvgBeginPath(vg)
        nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 6 * ps, 6 * ps * 0.4)
        local baseGlowA = math.floor(18 + 12 * glowFlick)
        nvgFillColor(vg, nvgRGBA(200, 50, 10, baseGlowA))
        nvgFill(vg)

        if activated then
            -- 点燃状态：增强像素火焰
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

            -- 增强火焰光晕（多层）
            local glowA1 = math.floor(30 + 20 * flicker1)
            nvgBeginPath(vg)
            nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 2 * ps, 12)
            nvgFillColor(vg, nvgRGBA(255, 150, 30, glowA1))
            nvgFill(vg)
            local glowA2 = math.floor(12 + 8 * flicker2)
            nvgBeginPath(vg)
            nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 2 * ps, 20)
            nvgFillColor(vg, nvgRGBA(255, 100, 10, glowA2))
            nvgFill(vg)

            -- 产生上升火花粒子
            M.SpawnFlameParticles(key)
        else
            -- 未点燃：发红光的余烬
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

            -- 产生缓慢上升的余烬粒子
            M.SpawnEmberParticles(key)
        end

        -- 绘制篝火粒子
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

        -- 点燃触发特效
        local ignite = M.campfireIgniteEffect[key]
        if ignite then
            local progress = ignite.timer / ignite.duration
            if progress < 0.15 then
                local flashA = math.floor(160 * (1.0 - progress / 0.15))
                nvgBeginPath(vg)
                nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 4 * ps, 20 + 14 * (progress / 0.15))
                nvgFillColor(vg, nvgRGBA(255, 220, 100, flashA))
                nvgFill(vg)
            end
            if progress > 0.05 and progress < 0.6 then
                local ringProgress = (progress - 0.05) / 0.55
                local ringR = 7 + 24 * ringProgress
                local ringA = math.floor(180 * (1.0 - ringProgress))
                nvgBeginPath(vg)
                nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 4 * ps, ringR)
                nvgStrokeColor(vg, nvgRGBA(255, 100, 20, ringA))
                nvgStrokeWidth(vg, 2.5 - 1.5 * ringProgress)
                nvgStroke(vg)
            end
            if progress < 0.4 then
                local pulseA = math.floor(100 * (1.0 - progress / 0.4))
                nvgBeginPath(vg)
                nvgCircle(vg, drawLeftX + 5 * ps, drawTopY + 5 * ps, 18)
                nvgFillColor(vg, nvgRGBA(255, 120, 20, pulseA))
                nvgFill(vg)
            end
        end
    end

    -- ====================================================================
    -- 像素风格火苗道具渲染
    -- ====================================================================
    function M.DrawFuelPixelFlame(px, py, col, row)
        local vg = M.vg
        local GRID = Config.GRID
        local ps = 2  -- 像素块大小
        local t = M.gameTime
        -- 火苗形状 (5x7 像素点阵，尖顶宽底小火苗)
        -- 使用两帧动画交替，模拟火焰摇曳
        local frame = math.floor(t * 6 + col * 1.3) % 3
        local shapes = {
            -- 帧0: 正常
            {
                {0,0,1,0,0},
                {0,1,1,0,0},
                {0,1,1,1,0},
                {1,1,1,1,0},
                {1,1,1,1,1},
                {0,1,1,1,0},
                {0,0,1,0,0},
            },
            -- 帧1: 略偏右
            {
                {0,0,0,1,0},
                {0,0,1,1,0},
                {0,1,1,1,0},
                {0,1,1,1,1},
                {1,1,1,1,0},
                {0,1,1,1,0},
                {0,0,1,0,0},
            },
            -- 帧2: 略偏左
            {
                {0,1,0,0,0},
                {0,1,1,0,0},
                {1,1,1,0,0},
                {1,1,1,1,0},
                {0,1,1,1,1},
                {0,1,1,1,0},
                {0,0,1,0,0},
            },
        }
        local shape = shapes[frame + 1]

        -- 暖色渐变：顶部亮黄 → 底部深橙
        local colors = {
            {255, 255, 180},  -- 亮黄白（顶）
            {255, 230, 100},  -- 黄
            {255, 190, 50},   -- 金黄
            {255, 150, 30},   -- 橙
            {255, 120, 20},   -- 深橙
            {255, 90, 10},    -- 红橙
            {200, 60, 5},     -- 深红（底）
        }

        -- 浮动偏移
        local floatY = math.sin(t * 4 + col * 2.3) * 1.5
        -- 渲染起点（居中）
        local startX = px + (GRID - 5 * ps) * 0.5
        local startY = py + (GRID - 7 * ps) * 0.5 + floatY

        -- 绘制外部光晕
        local glowFlicker = math.sin(t * 7 + col * 3.1) * 0.3 + 0.7
        nvgBeginPath(vg)
        nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5 + floatY, 7 * glowFlicker)
        nvgFillColor(vg, nvgRGBA(255, 150, 30, math.floor(35 * glowFlicker)))
        nvgFill(vg)

        -- 绘制像素火苗
        for r = 1, 7 do
            for c = 1, 5 do
                if shape[r][c] == 1 then
                    local drawX = startX + (c - 1) * ps
                    local drawY = startY + (r - 1) * ps
                    local baseColor = colors[r]
                    -- 轻微闪烁
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

        -- 顶部火星（小粒子随机弹出）
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

    -- ====================================================================
    -- 能力点渲染（像素化燃烧灯）
    -- ====================================================================
    function M.DrawAbilityPointTile(px, py, row, col)
        local vg = M.vg
        local GRID = Config.GRID
        local ps = 3  -- 像素块大小（更大更醒目）
        local t = M.gameTime

        -- 7x7 像素火球形状（圆形）
        local shape = {
            {0,0,1,1,1,0,0},
            {0,1,1,1,1,1,0},
            {1,1,1,1,1,1,1},
            {1,1,1,1,1,1,1},
            {1,1,1,1,1,1,1},
            {0,1,1,1,1,1,0},
            {0,0,1,1,1,0,0},
        }

        -- 4帧旋转动画（核心高光位置旋转模拟自转）
        local frame = math.floor(t * 6 + col * 1.3) % 4
        local coreFrames = {
            { -- 高光偏左上
                {0,0,0,0,0,0,0},
                {0,0,0,1,0,0,0},
                {0,0,1,1,1,0,0},
                {0,0,1,1,0,0,0},
                {0,0,0,1,0,0,0},
                {0,0,0,0,0,0,0},
                {0,0,0,0,0,0,0},
            },
            { -- 高光偏左下
                {0,0,0,0,0,0,0},
                {0,0,0,0,0,0,0},
                {0,0,1,1,0,0,0},
                {0,0,1,1,1,0,0},
                {0,0,0,1,1,0,0},
                {0,0,0,0,0,0,0},
                {0,0,0,0,0,0,0},
            },
            { -- 高光偏右下
                {0,0,0,0,0,0,0},
                {0,0,0,0,0,0,0},
                {0,0,0,1,0,0,0},
                {0,0,0,1,1,0,0},
                {0,0,1,1,1,0,0},
                {0,0,0,1,0,0,0},
                {0,0,0,0,0,0,0},
            },
            { -- 高光偏右上
                {0,0,0,0,0,0,0},
                {0,0,0,0,0,0,0},
                {0,0,0,1,1,0,0},
                {0,0,1,1,1,0,0},
                {0,0,1,1,0,0,0},
                {0,0,0,0,0,0,0},
                {0,0,0,0,0,0,0},
            },
        }
        local coreMask = coreFrames[frame + 1]

        -- 浮动动画
        local floatY = math.sin(t * 3 + col * 2.1) * 1.5

        local totalSize = 7 * ps
        local startX = px + (GRID - totalSize) * 0.5
        local startY = py + (GRID - totalSize) * 0.5 + floatY

        -- 外部光晕（橙色脉冲）
        local glowPulse = math.sin(t * 5 + col * 2.7) * 0.3 + 0.7
        nvgBeginPath(vg)
        nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5 + floatY, 10 * glowPulse)
        nvgFillColor(vg, nvgRGBA(255, 140, 30, math.floor(45 * glowPulse)))
        nvgFill(vg)

        -- 绘制火球像素
        for r = 1, 7 do
            for c = 1, 7 do
                if shape[r][c] == 1 then
                    local drawX = startX + (c - 1) * ps
                    local drawY = startY + (r - 1) * ps
                    -- 到中心的距离决定基础颜色
                    local dx = c - 4
                    local dy = r - 4
                    local dist = math.sqrt(dx * dx + dy * dy)
                    local cr, cg, cb
                    if coreMask[r][c] == 1 then
                        -- 旋转核心高光：亮白黄
                        cr, cg, cb = 255, 255, 220
                    elseif dist < 1.5 then
                        -- 内核：明黄
                        cr, cg, cb = 255, 230, 80
                    elseif dist < 2.5 then
                        -- 中层：橙黄
                        cr, cg, cb = 255, 160, 40
                    else
                        -- 外层：橙红
                        cr, cg, cb = 230, 80, 20
                    end
                    -- 像素闪烁
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

        -- 顶部火星粒子
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

        -- 侧面小火星（模拟旋转飞溅）
        local sideSparkAngle = t * 4 + col * 1.5
        for i = 1, 2 do
            local angle = sideSparkAngle + i * math.pi
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
end

return Tiles
