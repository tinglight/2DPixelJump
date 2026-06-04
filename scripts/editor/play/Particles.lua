------------------------------------------------------------
-- editor/play/Particles.lua — 粒子与视觉特效系统
------------------------------------------------------------
local Particles = {}

function Particles.Attach(M)

    local C = require("editor.Constants")
    local S = require("editor.State")
    local FlameDashChain = require("gameplay.FlameDashChain")

    -- 灯火跃迁流光拖尾粒子（模块级局部量）
    local dashTrailParticles = {}

    --- 重置冲刺拖尾粒子（由 M._ResetPlayState 调用）
    function M._resetDashTrailParticles()
        dashTrailParticles = {}
    end

    ------------------------------------------------------------
    -- 火焰时间 & 尖端像素
    ------------------------------------------------------------

    function M.UpdateFlameTime(dt)
        S.flameTime = S.flameTime + dt
        S.flameAnimTimer = S.flameAnimTimer + dt
        local frameInterval = 1.0 / C.FLAME_ANIM_FPS
        if S.flameAnimTimer >= frameInterval then
            S.flameAnimTimer = S.flameAnimTimer - frameInterval
            S.flameAnimFrame = S.flameAnimFrame + 1
        end
    end

    function M.UpdateTipPixels(dt)
        local N = C.FLAME_CFG.pixelGridSize
        S.tipSpawnTimer = S.tipSpawnTimer + dt
        local spawnInterval = M.GetTipSpawnInterval()

        if S.tipSpawnTimer >= spawnInterval and #S.tipPixels < 6 then
            S.tipSpawnTimer = 0
            M.SpawnTipPixel(N)
        end
        M.AgeTipPixels(dt)
    end

    function M.GetTipSpawnInterval()
        if not S.play.isOnGround and not S.play.isJumping then return 0.06 end
        if S.play.isMoving then return 0.08 end
        return 0.15
    end

    function M.SpawnTipPixel(N)
        local candidates = {}
        for col = 1, N do
            if S.pixelState[1][col] then
                table.insert(candidates, col)
            elseif S.pixelState[2] and S.pixelState[2][col] then
                table.insert(candidates, col)
            end
        end
        if #candidates == 0 then return end
        local srcCol = candidates[math.random(#candidates)]
        local life = 0.3 + math.random() * 0.4
        table.insert(S.tipPixels, {
            col = srcCol, row = 0,
            offX = math.random(-1, 1),
            offY = -math.random(1, 2),
            life = life, maxLife = life,
            phase = math.random() * 6.28,
            colorRow = math.random(1, 2),
        })
    end

    function M.AgeTipPixels(dt)
        local i = 1
        while i <= #S.tipPixels do
            local tp = S.tipPixels[i]
            tp.life = tp.life - dt
            if math.random() < dt * 4 then
                tp.offX = tp.offX + (math.random() > 0.5 and 1 or -1)
                tp.offX = math.max(-2, math.min(2, tp.offX))
            end
            if math.random() < dt * 3 then
                tp.offY = tp.offY - 1
            end
            if tp.life <= 0 then
                table.remove(S.tipPixels, i)
            else
                i = i + 1
            end
        end
    end

    ------------------------------------------------------------
    -- 坠落粒子
    ------------------------------------------------------------

    function M.UpdateFallParticles(dt)
        local isFalling = not S.play.isOnGround and not S.play.isJumping
        if isFalling and S.playAlivePixels < S.playTotalPixels then
            M.SpawnFallParticles()
        end
        M.AgeFallParticles(dt)
    end

    function M.SpawnFallParticles()
        local consumeRatio = 1.0 - S.playAlivePixels / math.max(1, S.playTotalPixels)
        local baseRatio = math.max(0.15, consumeRatio)
        local maxP = math.floor(4 + baseRatio * 14)
        local spawnChance = 0.40 + baseRatio * 0.50
        local attempts = 1 + math.floor(baseRatio * 2)
        local groundY = M.FindGroundY()
        local pPS = C.FLAME_CFG.pixelSize
        local totalSize = C.FLAME_CFG.pixelGridSize * pPS

        for _ = 1, attempts do
            if math.random() < spawnChance and #S.playFallParticles < maxP then
                M.EmitFallParticle(totalSize, pPS, groundY, consumeRatio)
            end
        end
    end

    function M.FindGroundY()
        local playerS = M.PlayerGridSize()
        local feetGridY = S.play.gridY + playerS
        local groundGridY = feetGridY
        for searchY = feetGridY, S.MAP_ROWS do
            if M.IsSolid(S.play.gridX, searchY) then
                groundGridY = searchY
                break
            end
            if searchY == S.MAP_ROWS then groundGridY = S.MAP_ROWS + 1 end
        end
        return (groundGridY - 1) * C.GRID
    end

    function M.EmitFallParticle(totalSize, pPS, groundY, consumeRatio)
        local worldX = (S.play.gridX - 1) * C.GRID
        local baseY = (S.play.gridY - 1) * C.GRID
        local side = math.random() > 0.5 and 1 or -1
        local emitX = worldX + totalSize * 0.5 + side * (totalSize * 0.3 + math.random() * totalSize * 0.2)
        local emitY = baseY + totalSize * (0.3 + math.random() * 0.5)
        local speedMul = 0.7 + consumeRatio * 0.6
        local life = 1.2 + consumeRatio * 0.6 + math.random() * 0.3
        table.insert(S.playFallParticles, {
            x = emitX, y = emitY,
            vx = side * (30 + math.random() * 40) * speedMul,
            vy = -(20 + math.random() * 30) * speedMul,
            life = life, maxLife = life, size = pPS,
            gravity = 120 + math.random() * 40,
            colorRow = math.random(5, 10),
            groundY = groundY,
            bounces = 0, maxBounces = 1 + math.floor(math.random() * 2),
        })
    end

    function M.AgeFallParticles(dt)
        local i = 1
        while i <= #S.playFallParticles do
            local p = S.playFallParticles[i]
            p.life = p.life - dt
            if p.life <= 0 then
                table.remove(S.playFallParticles, i)
            else
                p.vy = p.vy + p.gravity * dt
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                if p.y >= p.groundY and p.vy > 0 then
                    if p.bounces < p.maxBounces then
                        p.vy = -p.vy * 0.4
                        p.vx = p.vx * 0.6
                        p.y = p.groundY
                        p.bounces = p.bounces + 1
                    else
                        p.y = p.groundY
                        p.vy = 0
                        p.vx = p.vx * 0.9
                    end
                end
                i = i + 1
            end
        end
    end

    ------------------------------------------------------------
    -- 灯火跃迁流光特效
    ------------------------------------------------------------

    function M.DrawDashStreakEffect(vg)
        local flyX, flyY = FlameDashChain.GetFlyPosition()
        local dashState = FlameDashChain.GetState()
        local ps = C.FLAME_CFG.pixelSize
        local N = C.FLAME_CFG.pixelGridSize
        local totalSize = N * ps

        local screenX = (flyX - 1) * C.GRID - S.playCameraX + totalSize * 0.5
        local screenY = (flyY - 1) * C.GRID - S.playCameraY + totalSize * 0.5

        -- 生成拖尾粒子
        if dashState == "flying" or dashState == "falling" then
            for _ = 1, 2 do
                table.insert(dashTrailParticles, {
                    x = screenX + (math.random() - 0.5) * totalSize * 0.4,
                    y = screenY + (math.random() - 0.5) * totalSize * 0.4,
                    life = 0.3 + math.random() * 0.2,
                    maxLife = 0.5,
                    size = 2 + math.random() * 3,
                })
            end
        end

        -- 绘制拖尾粒子
        local i = 1
        while i <= #dashTrailParticles do
            local p = dashTrailParticles[i]
            p.life = p.life - (1.0 / 60.0)
            if p.life <= 0 then
                table.remove(dashTrailParticles, i)
            else
                local alpha = math.floor(180 * (p.life / p.maxLife))
                local size = p.size * (p.life / p.maxLife)
                nvgBeginPath(vg)
                nvgCircle(vg, p.x, p.y, size)
                nvgFillColor(vg, nvgRGBA(255, 180, 50, alpha))
                nvgFill(vg)
                i = i + 1
            end
        end

        -- 计算飞行方向角度
        local angle = 0
        if dashState == "flying" then
            local targetCol, targetRow = FlameDashChain.GetTarget()
            if targetCol and targetRow then
                local tgtX = (targetCol - 1) * C.GRID - S.playCameraX
                local tgtY = (targetRow - 1) * C.GRID - S.playCameraY
                angle = math.atan(tgtY - screenY, tgtX - screenX)
            end
        elseif dashState == "falling" then
            angle = math.pi / 2
        end

        -- 绘制流光核心（拉伸椭圆 + 外发光）
        nvgSave(vg)
        nvgTranslate(vg, screenX, screenY)
        nvgRotate(vg, angle)

        local glowW = totalSize * 1.2
        local glowH = totalSize * 0.5
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, 0, glowW, glowH)
        local glowPaint = nvgRadialGradient(vg, 0, 0, glowW * 0.2, glowW,
            nvgRGBA(255, 200, 80, 120), nvgRGBA(255, 120, 0, 0))
        nvgFillPaint(vg, glowPaint)
        nvgFill(vg)

        local coreW = totalSize * 0.6
        local coreH = totalSize * 0.25
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, 0, coreW, coreH)
        local corePaint = nvgRadialGradient(vg, 0, 0, coreW * 0.1, coreW * 0.8,
            nvgRGBA(255, 255, 240, 240), nvgRGBA(255, 180, 50, 80))
        nvgFillPaint(vg, corePaint)
        nvgFill(vg)

        nvgRestore(vg)

        -- 到达灯时的闪光效果
        if dashState == "arriving" then
            local flashAlpha = math.floor(200 * math.max(0, 1 - (S.playGameTime % 0.2) * 5))
            nvgBeginPath(vg)
            nvgCircle(vg, screenX, screenY, totalSize * 0.8)
            local flashPaint = nvgRadialGradient(vg, screenX, screenY, 0, totalSize * 0.8,
                nvgRGBA(255, 240, 200, flashAlpha), nvgRGBA(255, 200, 100, 0))
            nvgFillPaint(vg, flashPaint)
            nvgFill(vg)
        end
    end

    ------------------------------------------------------------
    -- 篝火/营火消息
    ------------------------------------------------------------

    M.bonfireMsg = { active = false, timer = 0, duration = 1.8 }

    function M.ShowBonfireMessage()
        M.bonfireMsg.active = true
        M.bonfireMsg.timer = 0
    end

    function M.UpdateBonfireMessage(dt)
        if M.bonfireMsg.active then
            M.bonfireMsg.timer = M.bonfireMsg.timer + dt
            if M.bonfireMsg.timer >= M.bonfireMsg.duration then
                M.bonfireMsg.active = false
            end
        end
    end

    ------------------------------------------------------------
    -- 篝火粒子系统
    ------------------------------------------------------------

    M.campfireParticles = {}
    M.campfireIgniteEffect = {}

    --- 触发篝火点燃爆发特效
    function M.TriggerCampfireIgnite(key)
        M.campfireIgniteEffect[key] = { timer = 0, duration = 1.2 }
        if not M.campfireParticles[key] then M.campfireParticles[key] = {} end
        for i = 1, 24 do
            table.insert(M.campfireParticles[key], {
                x = (math.random() - 0.5) * 12,
                y = -math.random() * 8,
                vx = (math.random() - 0.5) * 40,
                vy = -math.random() * 60 - 20,
                life = 0.6 + math.random() * 0.6,
                maxLife = 0.6 + math.random() * 0.6,
                size = math.random(2, 4),
                r = math.random(200, 255),
                g = math.random(80, 180),
                b = math.random(0, 40),
            })
        end
    end

    --- 更新篝火粒子系统
    function M.UpdateCampfireParticles(dt)
        for key, particles in pairs(M.campfireParticles) do
            local i = 1
            while i <= #particles do
                local p = particles[i]
                p.life = p.life - dt
                if p.life <= 0 then
                    table.remove(particles, i)
                else
                    p.x = p.x + p.vx * dt
                    p.y = p.y + p.vy * dt
                    p.vy = p.vy - 30 * dt
                    i = i + 1
                end
            end
        end
        for key, eff in pairs(M.campfireIgniteEffect) do
            eff.timer = eff.timer + dt
            if eff.timer >= eff.duration then
                M.campfireIgniteEffect[key] = nil
            end
        end
    end

    --- 为未点燃的篝火产生缓慢上升的余烬粒子
    function M.SpawnEmberParticles(key)
        if not M.campfireParticles[key] then M.campfireParticles[key] = {} end
        local particles = M.campfireParticles[key]
        if #particles < 6 then
            if math.random() < 0.03 then
                table.insert(particles, {
                    x = (math.random() - 0.5) * 10,
                    y = 0,
                    vx = (math.random() - 0.5) * 6,
                    vy = -math.random() * 15 - 5,
                    life = 1.0 + math.random() * 1.0,
                    maxLife = 1.0 + math.random() * 1.0,
                    size = math.random(1, 2),
                    r = math.random(180, 255),
                    g = math.random(40, 80),
                    b = 0,
                })
            end
        end
    end

    --- 为已点燃的篝火产生上升火花粒子
    function M.SpawnFlameParticles(key)
        if not M.campfireParticles[key] then M.campfireParticles[key] = {} end
        local particles = M.campfireParticles[key]
        if #particles < 14 then
            if math.random() < 0.12 then
                table.insert(particles, {
                    x = (math.random() - 0.5) * 14,
                    y = -math.random() * 6,
                    vx = (math.random() - 0.5) * 12,
                    vy = -math.random() * 35 - 15,
                    life = 0.5 + math.random() * 0.8,
                    maxLife = 0.5 + math.random() * 0.8,
                    size = math.random(1, 3),
                    r = 255,
                    g = math.random(120, 220),
                    b = math.random(0, 50),
                })
            end
        end
    end

    ------------------------------------------------------------
    -- 火苗爆裂粒子系统
    ------------------------------------------------------------

    M.fuelBurstParticles = {}

    function M.TriggerFuelBurst(worldX, worldY)
        local ps = 2
        for i = 1, 16 do
            local angle = (i / 16) * math.pi * 2 + math.random() * 0.4
            local speed = 30 + math.random() * 40
            local colorIdx = math.random(1, 5)
            local colors = {
                {255, 240, 120}, {255, 200, 60}, {255, 150, 30},
                {255, 100, 20}, {255, 80, 10},
            }
            local c = colors[colorIdx]
            table.insert(M.fuelBurstParticles, {
                x = worldX, y = worldY,
                vx = math.cos(angle) * speed,
                vy = math.sin(angle) * speed - 20,
                life = 0.5 + math.random() * 0.3,
                maxLife = 0.5 + math.random() * 0.3,
                size = ps, r = c[1], g = c[2], b = c[3],
            })
        end
    end

    function M.UpdateFuelBurst(dt)
        for i = #M.fuelBurstParticles, 1, -1 do
            local p = M.fuelBurstParticles[i]
            p.life = p.life - dt
            if p.life <= 0 then
                table.remove(M.fuelBurstParticles, i)
            else
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                p.vy = p.vy + 60 * dt
                p.vx = p.vx * 0.97
            end
        end
    end

    function M.DrawFuelBurst(vg, camX, camY)
        for _, p in ipairs(M.fuelBurstParticles) do
            local lifeRatio = p.life / p.maxLife
            local alpha = math.floor(lifeRatio * 255)
            local screenX = p.x - camX
            local screenY = p.y - camY
            local drawSize = p.size * (0.5 + lifeRatio * 0.5)
            local drawX = math.floor(screenX / p.size) * p.size
            local drawY = math.floor(screenY / p.size) * p.size
            nvgBeginPath(vg)
            nvgRect(vg, drawX, drawY, drawSize, drawSize)
            nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, alpha))
            nvgFill(vg)
            if lifeRatio > 0.3 then
                local tailX = drawX - math.floor(p.vx * 0.015 / p.size) * p.size
                local tailY = drawY - math.floor(p.vy * 0.015 / p.size) * p.size
                nvgBeginPath(vg)
                nvgRect(vg, tailX, tailY, drawSize, drawSize)
                nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(alpha * 0.4)))
                nvgFill(vg)
            end
        end
    end

    ------------------------------------------------------------
    -- 像素恢复过渡动画
    ------------------------------------------------------------

    M.pixelRecoverAnim = {
        active = false,
        pendingPixels = 0,
        recoveredPixels = 0,
        rate = 0,
        timer = 0,
        flashTimer = 0,
        flashActive = false,
    }

    function M.StartPixelRecoverAnim(totalToRecover)
        local anim = M.pixelRecoverAnim
        anim.active = true
        anim.pendingPixels = totalToRecover
        anim.recoveredPixels = 0
        anim.rate = totalToRecover / 0.6
        anim.timer = 0
        anim.flashTimer = 0
        anim.flashActive = true
    end

    function M.UpdatePixelRecoverAnim(dt)
        local anim = M.pixelRecoverAnim
        if not anim.active then return end
        anim.timer = anim.timer + dt
        anim.flashTimer = anim.flashTimer + dt
        local toRecover = math.floor(anim.rate * dt + 0.5)
        toRecover = math.min(toRecover, anim.pendingPixels - anim.recoveredPixels)
        if toRecover > 0 then
            M.RecoverPixels(toRecover)
        end
        anim.recoveredPixels = anim.recoveredPixels + toRecover
        if anim.recoveredPixels >= anim.pendingPixels then
            anim.active = false
            anim.flashActive = false
        end
        if anim.flashTimer > 0.8 then
            anim.flashActive = false
        end
    end

    function M.GetRecoverFlashIntensity()
        local anim = M.pixelRecoverAnim
        if not anim.flashActive then return 0 end
        local progress = anim.recoveredPixels / math.max(1, anim.pendingPixels)
        return (1.0 - progress) * 0.6
    end

end

return Particles
