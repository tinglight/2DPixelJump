------------------------------------------------------------
-- editor/PipeSystem.lua — 管道流水粒子系统
-- 5x5 大圆形排水管（无背景） + 直条型水流 + 流水音效
------------------------------------------------------------
local C = require("editor.Constants")
local S = require("editor.State")
local TileUtils = require("editor.TileUtils")

local M = {}

-- 管道实例列表
M.pipes = {}
-- 溅射粒子池
M.splashes = {}

-- 音频相关
local waterSound = nil
local waterSoundNode = nil
---@type SoundSource
local waterSoundSource = nil

------------------------------------------------------------
-- 初始化：扫描地图找到所有管道锚点 + 启动音效
------------------------------------------------------------
function M.Init()
    M.pipes = {}
    M.splashes = {}

    for row = 1, S.MAP_ROWS do
        for col = 1, S.MAP_COLS do
            local val = S.levelData[row][col]
            local base = TileUtils.GetTileType(val)
            if base == C.TILE.PIPE then
                -- 左上角锚点判断
                local isAnchor = true
                if col > 1 then
                    if TileUtils.GetTileType(S.levelData[row][col - 1]) == C.TILE.PIPE then
                        isAnchor = false
                    end
                end
                if isAnchor and row > 1 then
                    if TileUtils.GetTileType(S.levelData[row - 1][col]) == C.TILE.PIPE then
                        isAnchor = false
                    end
                end

                if isAnchor then
                    local switchGroup, waterTypeIndex = TileUtils.ParsePipeValue(val)
                    table.insert(M.pipes, {
                        col = col,
                        row = row,
                        waterTypeIndex = waterTypeIndex,
                        switchGroup = switchGroup,
                        particles = {},
                        emitAccum = 0,
                    })
                end
            end
        end
    end

    -- 初始化水流音效（循环播放）
    M.InitSound()
end

------------------------------------------------------------
-- 音效初始化（使用独立 Scene 承载 SoundSource）
------------------------------------------------------------
local audioScene = nil

function M.InitSound()
    -- 加载音效资源
    waterSound = cache:GetResource("Sound", "audio/sfx/pipe_water_flow.ogg")
    if waterSound then
        waterSound.looped = true
    end

    -- 创建独立 Scene 承载音频（此项目无全局 scene_）
    audioScene = Scene()
    audioScene:CreateComponent("Octree")
    waterSoundNode = audioScene:CreateChild("PipeWaterSound")
    waterSoundSource = waterSoundNode:CreateComponent("SoundSource")
    waterSoundSource.soundType = "Effect"
    waterSoundSource.gain = 0  -- 初始静音，根据活跃管道数调整

    print("[PipeSystem] Sound initialized, waterSound=" .. tostring(waterSound ~= nil))
end

------------------------------------------------------------
-- 更新音效（根据是否有活跃管道来播放/停止）
------------------------------------------------------------
function M.UpdateSound()
    if not waterSoundSource or not waterSound then return end

    local anyActive = false
    for _, pipe in ipairs(M.pipes) do
        if M.IsPipeActive(pipe) then
            anyActive = true
            break
        end
    end

    if anyActive then
        if not waterSoundSource:IsPlaying() then
            waterSoundSource:Play(waterSound)
        end
        -- 音量渐入
        local targetGain = 0.35
        local curGain = waterSoundSource.gain
        waterSoundSource.gain = curGain + (targetGain - curGain) * 0.05
    else
        -- 音量渐出
        local curGain = waterSoundSource.gain
        if curGain > 0.01 then
            waterSoundSource.gain = curGain * 0.92
        else
            waterSoundSource.gain = 0
            if waterSoundSource:IsPlaying() then
                waterSoundSource:Stop()
            end
        end
    end
end

------------------------------------------------------------
-- 停止音效（退出 PlayMode 时调用）
------------------------------------------------------------
function M.StopSound()
    if waterSoundSource then
        waterSoundSource:Stop()
        waterSoundSource.gain = 0
    end
    if waterSoundNode then
        waterSoundNode:Remove()
        waterSoundNode = nil
        waterSoundSource = nil
    end
    if audioScene then
        audioScene:Dispose()
        audioScene = nil
    end
end

------------------------------------------------------------
-- 判断管道是否激活
------------------------------------------------------------
function M.IsPipeActive(pipe)
    if pipe.switchGroup == 0 then
        return true
    end
    return not S.play.switchState[pipe.switchGroup]
end

------------------------------------------------------------
-- 更新粒子系统
------------------------------------------------------------
function M.Update(dt)
    local G = C.GRID

    -- 计算玩家碰撞区域（每帧缓存一次）
    M.hitWaterType = nil
    local playerAlive = S.play and S.play.alive
    local plx1, ply1, plx2, ply2 = 0, 0, 0, 0
    if playerAlive then
        local playerSize = math.ceil((C.FLAME_CFG.pixelGridSize * C.FLAME_CFG.pixelSize) / G)
        plx1 = (S.play.gridX - 1) * G
        ply1 = (S.play.gridY - 1) * G
        plx2 = plx1 + playerSize * G
        ply2 = ply1 + playerSize * G
    end

    for _, pipe in ipairs(M.pipes) do
        local active = M.IsPipeActive(pipe)

        if active then
            pipe.emitAccum = pipe.emitAccum + C.PIPE_EMIT_RATE * dt
            while pipe.emitAccum >= 1.0 and #pipe.particles < C.PIPE_PARTICLE_MAX do
                pipe.emitAccum = pipe.emitAccum - 1.0
                M.EmitParticle(pipe)
            end
            if pipe.emitAccum >= 1.0 then
                pipe.emitAccum = 1.0
            end
        else
            pipe.emitAccum = 0
        end

        -- 更新粒子
        local i = 1
        while i <= #pipe.particles do
            local p = pipe.particles[i]
            p.vy = p.vy + C.PIPE_GRAVITY * dt
            -- 极小水平阻力，保持接近直线
            p.vx = p.vx * (1.0 - 3.0 * dt)
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.life = p.life - dt

            -- 玩家碰撞检测（在移除粒子之前）
            if playerAlive and not M.hitWaterType then
                if p.x >= plx1 and p.x <= plx2 and p.y >= ply1 and p.y <= ply2 then
                    M.hitWaterType = pipe.waterTypeIndex
                end
            end

            -- 碰撞检测（管道区域内不碰撞）
            local pcol = math.floor(p.x / G) + 1
            local prow = math.floor(p.y / G) + 1

            local hitSolid = false
            local hitWater = false

            local inPipeArea = (pcol >= pipe.col and pcol < pipe.col + C.PIPE_WIDTH
                and prow >= pipe.row and prow < pipe.row + C.PIPE_HEIGHT)

            if not inPipeArea then
                if prow > S.MAP_ROWS or pcol < 1 or pcol > S.MAP_COLS then
                    hitSolid = true
                elseif prow >= 1 then
                    local val = S.levelData[prow] and S.levelData[prow][pcol]
                    if val then
                        local base = TileUtils.GetTileType(val)
                        if base == C.TILE.SOLID or base == C.TILE.SOLID_PILLAR or base == C.TILE.SOLID_SEWER then
                            hitSolid = true
                        elseif base == C.TILE.WATER or base == C.TILE.POISON_WATER or base == C.TILE.BLACK_WATER then
                            hitWater = true
                        end
                    end
                end
            end

            if hitSolid or hitWater or p.life <= 0 then
                if hitSolid or hitWater then
                    M.SpawnSplash(p.x, p.y, pipe.waterTypeIndex)
                end
                table.remove(pipe.particles, i)
            else
                i = i + 1
            end
        end
    end

    -- 更新溅射粒子
    local si = 1
    while si <= #M.splashes do
        local sp = M.splashes[si]
        sp.vy = sp.vy + 120 * dt
        sp.x = sp.x + sp.vx * dt
        sp.y = sp.y + sp.vy * dt
        sp.life = sp.life - dt
        if sp.life <= 0 then
            table.remove(M.splashes, si)
        else
            si = si + 1
        end
    end

    -- 更新音效
    M.UpdateSound()
end

------------------------------------------------------------
-- 发射粒子（从管口底部边缘向下流出）
-- 管口中心 = 5x5 区域正中心，管口内径 = outerR * 0.62
-- 粒子从管口底边开始，限制在管口宽度内
------------------------------------------------------------
function M.EmitParticle(pipe)
    local G = C.GRID
    local PW = C.PIPE_WIDTH * G
    local PH = C.PIPE_HEIGHT * G
    local centerX = (pipe.col - 1) * G + PW * 0.5
    local centerY = (pipe.row - 1) * G + PH * 0.5

    -- 管口内径计算（和 DrawPipe 一致）
    local outerR = math.min(PW, PH) * 0.46
    local holeR = outerR * 0.62

    -- 粒子从管口底部边缘出发（圆心 + 内径）
    local emitY = centerY + holeR * 0.85

    -- 水平偏移限制在管口直径内
    local maxSpreadX = holeR * 0.6
    local spread = (math.random() - 0.5) * maxSpreadX

    local particle = {
        x = centerX + spread,
        y = emitY,
        vx = spread * 0.2,
        vy = C.PIPE_INITIAL_VY + math.random() * 15,
        life = 4.0,
        size = 2.5 + math.random() * 2.0,
    }
    table.insert(pipe.particles, particle)
end

------------------------------------------------------------
-- 溅射
------------------------------------------------------------
function M.SpawnSplash(x, y, waterTypeIndex)
    for _ = 1, C.PIPE_SPLASH_COUNT do
        local splash = {
            x = x,
            y = y,
            vx = (math.random() - 0.5) * 60,
            vy = -(30 + math.random() * 35),
            life = 0.3 + math.random() * 0.2,
            waterTypeIndex = waterTypeIndex,
        }
        table.insert(M.splashes, splash)
        if #M.splashes > 120 then
            table.remove(M.splashes, 1)
        end
    end
end

------------------------------------------------------------
-- 玩家碰撞检测（返回 Update 中缓存的结果）
------------------------------------------------------------
function M.CheckPlayerHit()
    return M.hitWaterType
end

------------------------------------------------------------
-- 渲染管道本体（5x5 大圆形排水管，无背景）
------------------------------------------------------------
function M.DrawPipe(vg, px, py, pipe)
    local G = C.GRID
    local PW = C.PIPE_WIDTH * G
    local PH = C.PIPE_HEIGHT * G
    local active = M.IsPipeActive(pipe)
    local wColor = C.PIPE_WATER_COLORS[C.PIPE_WATER_TYPES[pipe.waterTypeIndex]]
        or C.PIPE_WATER_COLORS[C.TILE.WATER]

    local cx = px + PW * 0.5
    local cy = py + PH * 0.5
    local outerR = math.min(PW, PH) * 0.46

    -- 管壁外圈（大金属圆管，无底板背景）
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, outerR)
    nvgFillColor(vg, nvgRGBA(62, 67, 78, 255))
    nvgFill(vg)

    -- 管壁中圈（立体层次）
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, outerR * 0.87)
    nvgFillColor(vg, nvgRGBA(80, 85, 98, 255))
    nvgFill(vg)

    -- 顶部高光弧
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, outerR * 0.80, -2.5, -0.6, 1)
    nvgStrokeColor(vg, nvgRGBA(150, 155, 170, 190))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    -- 底部暗影弧
    nvgBeginPath(vg)
    nvgArc(vg, cx, cy, outerR * 0.80, 0.6, 2.5, 1)
    nvgStrokeColor(vg, nvgRGBA(30, 32, 40, 160))
    nvgStrokeWidth(vg, 2.0)
    nvgStroke(vg)

    -- 管口黑洞
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, outerR * 0.62)
    nvgFillColor(vg, nvgRGBA(8, 10, 15, 255))
    nvgFill(vg)

    -- 管口内静态水面（底部积水）
    if active then
        local waterR = outerR * 0.55
        nvgBeginPath(vg)
        -- 只画底部半圆弧表示积水
        nvgArc(vg, cx, cy, waterR, 0.5, 2.64, 1)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(wColor[1], wColor[2], wColor[3], 160))
        nvgFill(vg)
    end

    -- 外圈轮廓
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, outerR)
    nvgStrokeColor(vg, nvgRGBA(35, 38, 45, 255))
    nvgStrokeWidth(vg, 2.0)
    nvgStroke(vg)

    -- 内圈边缘
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, outerR * 0.64)
    nvgStrokeColor(vg, nvgRGBA(45, 48, 58, 220))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 铆钉（8个）
    for i = 0, 7 do
        local a = i * 0.785 + 0.3
        local rx = cx + outerR * 0.77 * math.cos(a)
        local ry = cy + outerR * 0.77 * math.sin(a)
        nvgBeginPath(vg)
        nvgCircle(vg, rx, ry, 2.0)
        nvgFillColor(vg, nvgRGBA(105, 110, 122, 220))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, rx - 0.5, ry - 0.5, 0.8)
        nvgFillColor(vg, nvgRGBA(160, 165, 175, 100))
        nvgFill(vg)
    end

    -- 开关组指示器
    if pipe.switchGroup > 0 then
        local gc = C.GROUP_COLORS[pipe.switchGroup] or C.GROUP_COLORS[1]
        nvgBeginPath(vg)
        nvgCircle(vg, px + PW - 6, py + 6, 3.5)
        if active then
            nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 80))
        end
        nvgFill(vg)
    end

    -- 关闭标记
    if not active then
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - outerR * 0.3, cy - outerR * 0.3)
        nvgLineTo(vg, cx + outerR * 0.3, cy + outerR * 0.3)
        nvgMoveTo(vg, cx - outerR * 0.3, cy + outerR * 0.3)
        nvgLineTo(vg, cx + outerR * 0.3, cy - outerR * 0.3)
        nvgStrokeColor(vg, nvgRGBA(220, 50, 50, 220))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)
    end
end

------------------------------------------------------------
-- 渲染水流（直条型水柱 + 粒子细节）
------------------------------------------------------------
function M.DrawParticles(vg, cameraX, cameraY)
    cameraX = cameraX or 0
    cameraY = cameraY or 0
    for _, pipe in ipairs(M.pipes) do
        if M.IsPipeActive(pipe) and #pipe.particles > 0 then
            local wColor = C.PIPE_WATER_COLORS[C.PIPE_WATER_TYPES[pipe.waterTypeIndex]]
                or C.PIPE_WATER_COLORS[C.TILE.WATER]

            local G = C.GRID
            local PW = C.PIPE_WIDTH * G
            local PH = C.PIPE_HEIGHT * G
            local centerX = (pipe.col - 1) * G + PW * 0.5 - cameraX
            local centerY = (pipe.row - 1) * G + PH * 0.5 - cameraY

            -- 管口几何（与 DrawPipe 一致）
            local outerR = math.min(PW, PH) * 0.46
            local holeR = outerR * 0.62

            -- 水柱从管口底边开始
            local topY = centerY + holeR * 0.85
            local bottomY = topY

            for _, p in ipairs(pipe.particles) do
                local sy = p.y - cameraY
                if sy > bottomY then bottomY = sy end
            end

            -- 直条型水柱（宽度匹配管口内径）
            local streamW = holeR * 1.1
            if bottomY > topY + 4 then
                -- 主水柱：直条矩形
                nvgBeginPath(vg)
                nvgRoundedRect(vg, centerX - streamW * 0.5, topY,
                    streamW, bottomY - topY, 3)
                nvgFillColor(vg, nvgRGBA(wColor[1], wColor[2], wColor[3], 130))
                nvgFill(vg)

                -- 内层更亮的窄柱（核心水流）
                local coreW = streamW * 0.5
                nvgBeginPath(vg)
                nvgRoundedRect(vg, centerX - coreW * 0.5, topY,
                    coreW, (bottomY - topY) * 0.85, 2)
                nvgFillColor(vg, nvgRGBA(
                    math.min(255, wColor[1] + 40),
                    math.min(255, wColor[2] + 40),
                    math.min(255, wColor[3] + 40), 100))
                nvgFill(vg)

                -- 水柱中心高光线
                nvgBeginPath(vg)
                nvgRect(vg, centerX - 1, topY, 2, (bottomY - topY) * 0.7)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 35))
                nvgFill(vg)

                -- 水柱边缘细线（左右各一条，增加流动感）
                local edgeAlpha = math.floor(50 + math.sin(S.playGameTime * 8) * 15)
                nvgBeginPath(vg)
                nvgRect(vg, centerX - streamW * 0.45, topY + 2, 1, (bottomY - topY) * 0.6)
                nvgFillColor(vg, nvgRGBA(wColor[1], wColor[2], wColor[3], edgeAlpha))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, centerX + streamW * 0.43, topY + 4, 1, (bottomY - topY) * 0.55)
                nvgFillColor(vg, nvgRGBA(wColor[1], wColor[2], wColor[3], edgeAlpha))
                nvgFill(vg)
            end

            -- 粒子细节（在水柱上点缀水滴）
            for _, p in ipairs(pipe.particles) do
                local screenX = p.x - cameraX
                local screenY = p.y - cameraY
                local tailLen = math.min(p.vy * 0.035, 6)
                local alpha = math.floor(math.min(p.life * 2, 1.0) * 140)

                nvgBeginPath(vg)
                nvgRoundedRect(vg, screenX - p.size * 0.4, screenY - tailLen,
                    p.size * 0.8, p.size + tailLen, p.size * 0.3)
                nvgFillColor(vg, nvgRGBA(
                    math.min(255, wColor[1] + 30),
                    math.min(255, wColor[2] + 30),
                    math.min(255, wColor[3] + 30),
                    math.floor(alpha * 0.4)))
                nvgFill(vg)
            end
        end
    end

    -- 溅射粒子
    for _, sp in ipairs(M.splashes) do
        local screenX = sp.x - cameraX
        local screenY = sp.y - cameraY
        local wColor = C.PIPE_WATER_COLORS[C.PIPE_WATER_TYPES[sp.waterTypeIndex]]
            or C.PIPE_WATER_COLORS[C.TILE.WATER]
        local alpha = math.floor((sp.life / 0.5) * 180)

        nvgBeginPath(vg)
        nvgCircle(vg, screenX, screenY, 1.2)
        nvgFillColor(vg, nvgRGBA(
            math.min(255, wColor[1] + 40),
            math.min(255, wColor[2] + 40),
            math.min(255, wColor[3] + 40),
            alpha))
        nvgFill(vg)
    end
end

------------------------------------------------------------
-- 编辑器静态预览（5x5 大圆管简化版，无背景）
------------------------------------------------------------
function M.DrawPipeStatic(vg, px, py, val)
    local G = C.GRID
    local _, waterTypeIndex = TileUtils.ParsePipeValue(val)
    local switchGroup = select(1, TileUtils.ParsePipeValue(val))
    local wColor = C.PIPE_WATER_COLORS[C.PIPE_WATER_TYPES[waterTypeIndex]]
        or C.PIPE_WATER_COLORS[C.TILE.WATER]

    local cx = px + G * 0.5
    local cy = py + G * 0.5
    local outerR = G * 0.45

    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, outerR)
    nvgFillColor(vg, nvgRGBA(62, 67, 78, 255))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, outerR * 0.55)
    nvgFillColor(vg, nvgRGBA(15, 18, 25, 255))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy + outerR * 0.15, outerR * 0.28)
    nvgFillColor(vg, nvgRGBA(wColor[1], wColor[2], wColor[3], 200))
    nvgFill(vg)

    if switchGroup > 0 then
        local gc = C.GROUP_COLORS[switchGroup] or C.GROUP_COLORS[1]
        nvgBeginPath(vg)
        nvgCircle(vg, px + G - 3, py + 3, 2)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
        nvgFill(vg)
    end
end

return M
