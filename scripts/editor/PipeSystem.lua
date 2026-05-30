------------------------------------------------------------
-- editor/PipeSystem.lua — 管道流水粒子系统
-- 7x7 大圆形排水管（无背景） + 直条型水流 + 流水音效
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

            if hitSolid or p.life <= 0 then
                if hitSolid then
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
-- 管口中心 = 7x7 区域正中心，管口内径 = outerR * 0.62
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
        size = 4.0,
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
-- 渲染管道本体（7x7 像素风魂系排水管）
------------------------------------------------------------
function M.DrawPipe(vg, px, py, pipe)
    local G = C.GRID
    local PW = C.PIPE_WIDTH * G
    local PH = C.PIPE_HEIGHT * G
    local active = M.IsPipeActive(pipe)
    local wColor = C.PIPE_WATER_COLORS[C.PIPE_WATER_TYPES[pipe.waterTypeIndex]]
        or C.PIPE_WATER_COLORS[C.TILE.WATER]

    local PS = 4  -- 像素块尺寸
    local cx = px + PW * 0.5
    local cy = py + PH * 0.5
    local outerR = math.min(PW, PH) * 0.45
    local innerR = outerR * 0.62

    -- 辅助：用像素方块填充圆形区域
    local function fillPixelCircle(centerX, centerY, radius, r, g, b, a)
        local startX = math.floor((centerX - radius) / PS) * PS
        local startY = math.floor((centerY - radius) / PS) * PS
        local endX = math.floor((centerX + radius) / PS) * PS
        local endY = math.floor((centerY + radius) / PS) * PS
        for by = startY, endY, PS do
            for bx = startX, endX, PS do
                local dx = (bx + PS * 0.5) - centerX
                local dy = (by + PS * 0.5) - centerY
                if dx * dx + dy * dy <= radius * radius then
                    nvgBeginPath(vg)
                    nvgRect(vg, bx, by, PS, PS)
                    nvgFillColor(vg, nvgRGBA(r, g, b, a))
                    nvgFill(vg)
                end
            end
        end
    end

    -- 辅助：像素圆环（外圆减内圆）
    local function fillPixelRing(centerX, centerY, rOuter, rInner, r, g, b, a)
        local startX = math.floor((centerX - rOuter) / PS) * PS
        local startY = math.floor((centerY - rOuter) / PS) * PS
        local endX = math.floor((centerX + rOuter) / PS) * PS
        local endY = math.floor((centerY + rOuter) / PS) * PS
        for by = startY, endY, PS do
            for bx = startX, endX, PS do
                local dx = (bx + PS * 0.5) - centerX
                local dy = (by + PS * 0.5) - centerY
                local d2 = dx * dx + dy * dy
                if d2 <= rOuter * rOuter and d2 > rInner * rInner then
                    nvgBeginPath(vg)
                    nvgRect(vg, bx, by, PS, PS)
                    nvgFillColor(vg, nvgRGBA(r, g, b, a))
                    nvgFill(vg)
                end
            end
        end
    end

    -- 外圈管壁（黑灰）
    fillPixelRing(cx, cy, outerR, outerR * 0.85, 32, 34, 36, 255)

    -- 中圈管壁（深灰）
    fillPixelRing(cx, cy, outerR * 0.85, innerR, 48, 52, 50, 255)

    -- 墨绿高光（顶部弧形区域的像素块）
    local startX = math.floor((cx - outerR) / PS) * PS
    local endX = math.floor((cx + outerR) / PS) * PS
    local startY = math.floor((cy - outerR) / PS) * PS
    for by = startY, startY + math.floor(outerR * 0.4 / PS) * PS, PS do
        for bx = startX, endX, PS do
            local dx = (bx + PS * 0.5) - cx
            local dy = (by + PS * 0.5) - cy
            local d2 = dx * dx + dy * dy
            if d2 <= (outerR * 0.92) * (outerR * 0.92) and d2 > (outerR * 0.75) * (outerR * 0.75) then
                if dy < -outerR * 0.2 then
                    nvgBeginPath(vg)
                    nvgRect(vg, bx, by, PS, PS)
                    nvgFillColor(vg, nvgRGBA(45, 85, 62, 140))
                    nvgFill(vg)
                end
            end
        end
    end

    -- 管口黑洞（像素圆）
    fillPixelCircle(cx, cy, innerR, 8, 10, 12, 255)

    -- 管口底部积水（下半部分像素块）
    if active then
        local waterR = innerR * 0.88
        local wStartX = math.floor((cx - waterR) / PS) * PS
        local wEndX = math.floor((cx + waterR) / PS) * PS
        local wStartY = math.floor(cy / PS) * PS
        local wEndY = math.floor((cy + waterR) / PS) * PS
        for by = wStartY, wEndY, PS do
            for bx = wStartX, wEndX, PS do
                local dx = (bx + PS * 0.5) - cx
                local dy = (by + PS * 0.5) - cy
                if dx * dx + dy * dy <= waterR * waterR then
                    nvgBeginPath(vg)
                    nvgRect(vg, bx, by, PS, PS)
                    nvgFillColor(vg, nvgRGBA(wColor[1], wColor[2], wColor[3], 150))
                    nvgFill(vg)
                end
            end
        end
    end

    -- 墨绿苔痕像素点（伪随机）
    local seed = pipe.col * 31 + pipe.row * 17
    for i = 0, 4 do
        local angle = (seed * (i + 1) * 2.17) % (math.pi * 2)
        local dist = outerR * (0.72 + ((seed * (i + 3)) % 12) * 0.01)
        local dx = cx + math.cos(angle) * dist
        local dy = cy + math.sin(angle) * dist
        local bx = math.floor(dx / PS) * PS
        local by = math.floor(dy / PS) * PS
        nvgBeginPath(vg)
        nvgRect(vg, bx, by, PS, PS)
        nvgFillColor(vg, nvgRGBA(30, 70, 48, 180))
        nvgFill(vg)
    end

    -- 开关组指示器（像素方块）
    if pipe.switchGroup > 0 then
        local gc = C.GROUP_COLORS[pipe.switchGroup] or C.GROUP_COLORS[1]
        nvgBeginPath(vg)
        nvgRect(vg, px + PW - PS * 2, py + PS, PS, PS)
        if active then
            nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 80))
        end
        nvgFill(vg)
    end

    -- 关闭标记（像素 X）
    if not active then
        local markR = math.floor(innerR * 0.6 / PS) * PS
        for i = 0, markR / PS - 1 do
            local off = i * PS
            nvgBeginPath(vg)
            nvgRect(vg, cx - markR * 0.5 + off, cy - markR * 0.5 + off, PS, PS)
            nvgFillColor(vg, nvgRGBA(180, 40, 40, 220))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRect(vg, cx + markR * 0.5 - off - PS, cy - markR * 0.5 + off, PS, PS)
            nvgFillColor(vg, nvgRGBA(180, 40, 40, 220))
            nvgFill(vg)
        end
    end
end

------------------------------------------------------------
-- 渲染水流（像素风水柱 + 像素水滴，黑灰墨绿色调）
------------------------------------------------------------
function M.DrawParticles(vg, cameraX, cameraY)
    cameraX = cameraX or 0
    cameraY = cameraY or 0
    local PS = 4  -- 像素块尺寸

    for _, pipe in ipairs(M.pipes) do
        if M.IsPipeActive(pipe) and #pipe.particles > 0 then
            local wColor = C.PIPE_WATER_COLORS[C.PIPE_WATER_TYPES[pipe.waterTypeIndex]]
                or C.PIPE_WATER_COLORS[C.TILE.WATER]

            local G = C.GRID
            local PW = C.PIPE_WIDTH * G
            local PH = C.PIPE_HEIGHT * G
            local centerX = (pipe.col - 1) * G + PW * 0.5 - cameraX
            local centerY = (pipe.row - 1) * G + PH * 0.5 - cameraY
            local outerR = math.min(PW, PH) * 0.45
            local innerR = outerR * 0.62

            -- 水柱从管口底边开始
            local topY = centerY + innerR
            local bottomY = topY

            for _, p in ipairs(pipe.particles) do
                local sy = p.y - cameraY
                if sy > bottomY then bottomY = sy end
            end

            -- 像素水柱（方块列）
            local streamW = math.floor(innerR * 0.9 / PS) * PS
            if bottomY > topY + PS then
                local colX = math.floor((centerX - streamW * 0.5) / PS) * PS
                local colY = math.floor(topY / PS) * PS
                local colH = math.floor((bottomY - topY) / PS) * PS

                -- 主水柱
                nvgBeginPath(vg)
                nvgRect(vg, colX, colY, streamW, colH)
                nvgFillColor(vg, nvgRGBA(wColor[1], wColor[2], wColor[3], 110))
                nvgFill(vg)

                -- 核心亮柱（窄）
                local coreW = math.max(PS, math.floor(streamW * 0.4 / PS) * PS)
                local coreX = math.floor((centerX - coreW * 0.5) / PS) * PS
                nvgBeginPath(vg)
                nvgRect(vg, coreX, colY, coreW, math.floor(colH * 0.85 / PS) * PS)
                nvgFillColor(vg, nvgRGBA(
                    math.min(255, wColor[1] + 35),
                    math.min(255, wColor[2] + 35),
                    math.min(255, wColor[3] + 35), 80))
                nvgFill(vg)

                -- 墨绿色边缘像素列
                nvgBeginPath(vg)
                nvgRect(vg, colX, colY, PS, colH)
                nvgFillColor(vg, nvgRGBA(30, 70, 50, 70))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgRect(vg, colX + streamW - PS, colY, PS, colH)
                nvgFillColor(vg, nvgRGBA(30, 70, 50, 70))
                nvgFill(vg)

                -- 流动纹理（像素块滚动）
                local flowOffset = math.floor((S.playGameTime * 40) / PS) * PS
                for fy = colY, colY + colH - PS, PS * 3 do
                    local drawY = fy + (flowOffset % (PS * 3))
                    if drawY >= colY and drawY < colY + colH then
                        nvgBeginPath(vg)
                        nvgRect(vg, colX, drawY, PS, PS)
                        nvgFillColor(vg, nvgRGBA(wColor[1], wColor[2], wColor[3], 50))
                        nvgFill(vg)
                        nvgBeginPath(vg)
                        nvgRect(vg, colX + streamW - PS, drawY + PS, PS, PS)
                        nvgFillColor(vg, nvgRGBA(wColor[1], wColor[2], wColor[3], 50))
                        nvgFill(vg)
                    end
                end
            end

            -- 像素水滴粒子（方块）
            for _, p in ipairs(pipe.particles) do
                local screenX = math.floor((p.x - cameraX) / PS) * PS
                local screenY = math.floor((p.y - cameraY) / PS) * PS
                local alpha = math.floor(math.min(p.life * 2, 1.0) * 160)

                nvgBeginPath(vg)
                nvgRect(vg, screenX, screenY, PS, PS)
                nvgFillColor(vg, nvgRGBA(
                    math.min(255, wColor[1] + 25),
                    math.min(255, wColor[2] + 25),
                    math.min(255, wColor[3] + 25),
                    math.floor(alpha * 0.6)))
                nvgFill(vg)
            end
        end
    end

    -- 溅射粒子（像素方块）
    for _, sp in ipairs(M.splashes) do
        local screenX = math.floor((sp.x - cameraX) / PS) * PS
        local screenY = math.floor((sp.y - cameraY) / PS) * PS
        local wColor = C.PIPE_WATER_COLORS[C.PIPE_WATER_TYPES[sp.waterTypeIndex]]
            or C.PIPE_WATER_COLORS[C.TILE.WATER]
        local alpha = math.floor((sp.life / 0.5) * 180)

        nvgBeginPath(vg)
        nvgRect(vg, screenX, screenY, PS, PS)
        nvgFillColor(vg, nvgRGBA(
            math.min(255, wColor[1] + 40),
            math.min(255, wColor[2] + 40),
            math.min(255, wColor[3] + 40),
            alpha))
        nvgFill(vg)
    end
end

------------------------------------------------------------
-- 编辑器静态预览（7x7 像素风圆形管道缩略图，黑灰墨绿）
------------------------------------------------------------
function M.DrawPipeStatic(vg, px, py, val)
    local G = C.GRID
    local _, waterTypeIndex = TileUtils.ParsePipeValue(val)
    local switchGroup = select(1, TileUtils.ParsePipeValue(val))
    local wColor = C.PIPE_WATER_COLORS[C.PIPE_WATER_TYPES[waterTypeIndex]]
        or C.PIPE_WATER_COLORS[C.TILE.WATER]

    local PS = 2  -- 缩略图用小像素块
    local cx = px + G * 0.5
    local cy = py + G * 0.5
    local outerR = G * 0.42
    local innerR = outerR * 0.55

    -- 用像素方块画圆环管壁
    local startX = math.floor((cx - outerR) / PS) * PS
    local startY = math.floor((cy - outerR) / PS) * PS
    local endX = math.floor((cx + outerR) / PS) * PS
    local endY = math.floor((cy + outerR) / PS) * PS
    for by = startY, endY, PS do
        for bx = startX, endX, PS do
            local dx = (bx + PS * 0.5) - cx
            local dy = (by + PS * 0.5) - cy
            local d2 = dx * dx + dy * dy
            if d2 <= outerR * outerR then
                local r, g, b, a
                if d2 <= innerR * innerR then
                    -- 管口黑洞
                    r, g, b, a = 8, 10, 12, 255
                    -- 下半部分积水
                    if dy > 0 and d2 <= (innerR * 0.9) * (innerR * 0.9) then
                        r, g, b, a = wColor[1], wColor[2], wColor[3], 180
                    end
                elseif d2 > (outerR * 0.8) * (outerR * 0.8) then
                    -- 外圈黑灰
                    r, g, b, a = 32, 34, 36, 255
                else
                    -- 中圈深灰
                    r, g, b, a = 48, 52, 50, 255
                    -- 顶部墨绿高光
                    if dy < -outerR * 0.2 and d2 > (outerR * 0.65) * (outerR * 0.65) then
                        r, g, b, a = 42, 78, 58, 200
                    end
                end
                nvgBeginPath(vg)
                nvgRect(vg, bx, by, PS, PS)
                nvgFillColor(vg, nvgRGBA(r, g, b, a))
                nvgFill(vg)
            end
        end
    end

    -- 开关组指示
    if switchGroup > 0 then
        local gc = C.GROUP_COLORS[switchGroup] or C.GROUP_COLORS[1]
        nvgBeginPath(vg)
        nvgRect(vg, px + G - PS * 2, py, PS, PS)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
        nvgFill(vg)
    end
end

return M
