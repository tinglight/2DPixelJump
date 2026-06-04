------------------------------------------------------------
-- gameplay/render/Effects.lua — 特效渲染（篝火消息、粒子、恢复动画）
------------------------------------------------------------
local Effects = {}

function Effects.Attach(M)
    -- ====================================================================
    -- BONFIRE LIT 消息状态
    -- ====================================================================
    M.bonfireMessage = {
        active = false,
        timer = 0,
        duration = 2.5,
    }

    function M.ShowBonfireMessage()
        M.bonfireMessage.active = true
        M.bonfireMessage.timer = 0
    end

    -- 篝火粒子系统 (key -> particle list)
    M.campfireParticles = {}
    -- 篝火点燃特效状态 (key -> {timer, duration})
    M.campfireIgniteEffect = {}

    --- 触发篝火点燃爆发特效
    function M.TriggerCampfireIgnite(key)
        M.campfireIgniteEffect[key] = { timer = 0, duration = 1.2 }
        if not M.campfireParticles[key] then M.campfireParticles[key] = {} end
        for i = 1, 18 do
            table.insert(M.campfireParticles[key], {
                x = (math.random() - 0.5) * 8,
                y = -math.random() * 5,
                vx = (math.random() - 0.5) * 30,
                vy = -math.random() * 45 - 15,
                life = 0.5 + math.random() * 0.5,
                maxLife = 0.5 + math.random() * 0.5,
                size = math.random(1, 3),
                r = math.random(200, 255),
                g = math.random(80, 180),
                b = math.random(0, 40),
            })
        end
    end

    function M.UpdateBonfireMessage(dt)
        if M.bonfireMessage.active then
            M.bonfireMessage.timer = M.bonfireMessage.timer + dt
            if M.bonfireMessage.timer >= M.bonfireMessage.duration then
                M.bonfireMessage.active = false
            end
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
                    p.vy = p.vy - 20 * dt
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

    --- 为未点燃篝火产生余烬粒子
    function M.SpawnEmberParticles(key)
        if not M.campfireParticles[key] then M.campfireParticles[key] = {} end
        local particles = M.campfireParticles[key]
        if #particles < 4 then
            if math.random() < 0.025 then
                table.insert(particles, {
                    x = (math.random() - 0.5) * 6,
                    y = 0,
                    vx = (math.random() - 0.5) * 4,
                    vy = -math.random() * 10 - 3,
                    life = 0.8 + math.random() * 0.8,
                    maxLife = 0.8 + math.random() * 0.8,
                    size = 1,
                    r = math.random(180, 255),
                    g = math.random(40, 80),
                    b = 0,
                })
            end
        end
    end

    --- 为已点燃篝火产生火花粒子
    function M.SpawnFlameParticles(key)
        if not M.campfireParticles[key] then M.campfireParticles[key] = {} end
        local particles = M.campfireParticles[key]
        if #particles < 10 then
            if math.random() < 0.10 then
                table.insert(particles, {
                    x = (math.random() - 0.5) * 10,
                    y = -math.random() * 4,
                    vx = (math.random() - 0.5) * 8,
                    vy = -math.random() * 25 - 10,
                    life = 0.4 + math.random() * 0.6,
                    maxLife = 0.4 + math.random() * 0.6,
                    size = math.random(1, 2),
                    r = 255,
                    g = math.random(120, 220),
                    b = math.random(0, 50),
                })
            end
        end
    end

    -- ====================================================================
    -- 火苗拾取爆裂粒子系统
    -- ====================================================================
    M.fuelBurstParticles = {}

    --- 在指定位置触发火苗爆裂特效
    function M.TriggerFuelBurst(worldX, worldY)
        local ps = 2  -- 像素块大小
        for i = 1, 16 do
            local angle = (i / 16) * math.pi * 2 + math.random() * 0.4
            local speed = 30 + math.random() * 40
            local colorIdx = math.random(1, 5)
            -- 暖色调颜色组
            local colors = {
                {255, 240, 120},  -- 亮黄
                {255, 200, 60},   -- 金黄
                {255, 150, 30},   -- 橙色
                {255, 100, 20},   -- 深橙
                {255, 80, 10},    -- 红橙
            }
            local c = colors[colorIdx]
            table.insert(M.fuelBurstParticles, {
                x = worldX,
                y = worldY,
                vx = math.cos(angle) * speed,
                vy = math.sin(angle) * speed - 20,  -- 偏上方弹射
                life = 0.5 + math.random() * 0.3,
                maxLife = 0.5 + math.random() * 0.3,
                size = ps,
                r = c[1], g = c[2], b = c[3],
            })
        end
    end

    --- 更新火苗爆裂粒子
    function M.UpdateFuelBurst(dt)
        for i = #M.fuelBurstParticles, 1, -1 do
            local p = M.fuelBurstParticles[i]
            p.life = p.life - dt
            if p.life <= 0 then
                table.remove(M.fuelBurstParticles, i)
            else
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                p.vy = p.vy + 60 * dt  -- 重力
                p.vx = p.vx * 0.97  -- 阻力
            end
        end
    end

    --- 绘制火苗爆裂粒子
    function M.DrawFuelBurst()
        local vg = M.vg
        for _, p in ipairs(M.fuelBurstParticles) do
            local lifeRatio = p.life / p.maxLife
            local alpha = math.floor(lifeRatio * 255)
            local screenX = p.x - M.cameraX
            local drawSize = p.size * (0.5 + lifeRatio * 0.5)
            -- 像素对齐
            local drawX = math.floor(screenX / p.size) * p.size
            local drawY = math.floor(p.y / p.size) * p.size
            nvgBeginPath(vg)
            nvgRect(vg, drawX, drawY, drawSize, drawSize)
            nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, alpha))
            nvgFill(vg)
            -- 拖尾像素
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

    -- ====================================================================
    -- 火焰像素恢复过渡动画
    -- ====================================================================
    M.pixelRecoverAnim = {
        active = false,
        pendingPixels = 0,       -- 待恢复的总像素数
        recoveredPixels = 0,     -- 已恢复的像素数
        rate = 0,                -- 每秒恢复速度
        timer = 0,
        -- 闪光效果
        flashTimer = 0,
        flashActive = false,
    }

    --- 启动像素恢复过渡动画（替代瞬间恢复）
    function M.StartPixelRecoverAnim(totalToRecover)
        local anim = M.pixelRecoverAnim
        anim.active = true
        anim.pendingPixels = totalToRecover
        anim.recoveredPixels = 0
        -- 0.6 秒内恢复完毕，像素逐个出现
        anim.rate = totalToRecover / 0.6
        anim.timer = 0
        anim.flashTimer = 0
        anim.flashActive = true
    end

    --- 更新像素恢复动画
    function M.UpdatePixelRecoverAnim(dt)
        local anim = M.pixelRecoverAnim
        if not anim.active then return end

        anim.timer = anim.timer + dt
        anim.flashTimer = anim.flashTimer + dt

        -- 逐步恢复像素
        local toRecover = math.floor(anim.rate * dt + 0.5)
        toRecover = math.min(toRecover, anim.pendingPixels - anim.recoveredPixels)
        if toRecover > 0 then
            local PixelSystem = require("gameplay.PixelSystem")
            PixelSystem.RecoverPixels(toRecover)
            anim.recoveredPixels = anim.recoveredPixels + toRecover
        end

        -- 动画完成
        if anim.recoveredPixels >= anim.pendingPixels then
            anim.active = false
            anim.flashActive = false
        end

        -- 闪光在 0.8 秒后消失
        if anim.flashTimer > 0.8 then
            anim.flashActive = false
        end
    end

    --- 获取恢复动画进度（0~1），供玩家渲染时增加闪光效果
    function M.GetRecoverFlashIntensity()
        local anim = M.pixelRecoverAnim
        if not anim.flashActive then return 0 end
        local progress = anim.recoveredPixels / math.max(1, anim.pendingPixels)
        return (1.0 - progress) * 0.6
    end
end

return Effects
