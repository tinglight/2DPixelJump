------------------------------------------------------------
-- gameplay/Animation.lua — 表现层动画（灯笼晃动、粒子、压缩、火焰帧）
------------------------------------------------------------
local Config = require("gameplay.Config")

local M = {}

-- 依赖（通过 Inject 注入）
local Physics = nil
local PixelSystem = nil
local PlayerController = nil

function M.Inject(deps)
    Physics = deps.Physics
    PixelSystem = deps.PixelSystem
    PlayerController = deps.PlayerController
end

-- ====================================================================
-- 火焰像素动画帧系统
-- ====================================================================
local FLAME_ANIM_FPS = 10
M.flameAnimTimer = 0
M.flameAnimFrame = 0

-- 每行像素的偏移量
M.rowOffsets = {}
M.rowVOffsets = {}

--- 更新火焰动画帧
function M.UpdateFlameAnimFrame()
    M.flameAnimFrame = M.flameAnimFrame + 1
    local N = Config.PLAYER_CONFIG.pixelGridSize
    local player = PlayerController.player

    local maxAmp = 1
    local vertAmp = 0
    if not player.isOnGround and not player.isJumping then
        maxAmp = 2
    elseif player.isMoving then
        maxAmp = 2
    end

    for row = 1, N do
        local rowFactor = (N - row) / N
        local amp = math.floor(maxAmp * rowFactor + 0.5)
        local phase = M.flameAnimFrame * 0.7 - row * 0.8
        local rawWave = math.sin(phase)
        local intOffset = math.floor(rawWave * amp + 0.5)

        if player.isMoving then
            local leanDir = player.facingRight and 1 or -1
            local lean = math.floor(rowFactor * 1.5 + 0.5) * leanDir
            intOffset = intOffset + lean
        end

        M.rowOffsets[row] = intOffset
        M.rowVOffsets[row] = 0
    end
end

-- ====================================================================
-- 灯笼晃动
-- ====================================================================
M.lanternSway = {
    angle = 0,
    velocity = 0,
    active = false,
}

M.lanternRowShifts = {}
for i = 1, 10 do M.lanternRowShifts[i] = 0 end

function M.UpdateLanternSway(dt, gameTime)
    local player = PlayerController.player
    local PC = Config.PLAYER_CONFIG

    if player.isMoving then
        local swayForce = math.sin(gameTime * PC.lanternSwayFreq) * 25.0
        local dirBias = player.facingRight and 5.0 or -5.0
        M.lanternSway.velocity = M.lanternSway.velocity + (swayForce + dirBias) * dt
        M.lanternSway.active = true
    else
        if math.abs(M.lanternSway.angle) < 0.05 and math.abs(M.lanternSway.velocity) < 0.05 then
            M.lanternSway.angle = 0
            M.lanternSway.velocity = 0
            M.lanternSway.active = false
        end
    end

    local springK = 18.0
    M.lanternSway.velocity = M.lanternSway.velocity - M.lanternSway.angle * springK * dt
    local damping = player.isMoving and 2.5 or 4.0
    M.lanternSway.velocity = M.lanternSway.velocity * (1.0 - damping * dt)
    M.lanternSway.angle = M.lanternSway.angle + M.lanternSway.velocity * dt
    local maxA = PC.lanternMaxAngle
    M.lanternSway.angle = math.max(-maxA, math.min(maxA, M.lanternSway.angle))

    -- 计算每行偏移
    local N = PC.pixelGridSize
    local topOffset = M.lanternSway.angle
    for row = 1, N do
        local factor = ((N - row) / (N - 1)) ^ 1.5
        local rawOffset = topOffset * factor
        M.lanternRowShifts[row] = math.floor(rawOffset + 0.5)
    end
    M.lanternRowShifts[N] = 0
    for row = N - 1, 1, -1 do
        local diff = M.lanternRowShifts[row] - M.lanternRowShifts[row + 1]
        if diff > 1 then
            M.lanternRowShifts[row] = M.lanternRowShifts[row + 1] + 1
        elseif diff < -1 then
            M.lanternRowShifts[row] = M.lanternRowShifts[row + 1] - 1
        end
    end
end

-- ====================================================================
-- 下落火苗四散粒子
-- ====================================================================
M.fallParticles = {}
local fallParticleDebugTimer = 0

function M.UpdateFallParticles(dt, gameTime)
    local player = PlayerController.player
    local N = Config.PLAYER_CONFIG.pixelGridSize
    local ps = Config.PLAYER_CONFIG.pixelSize

    fallParticleDebugTimer = fallParticleDebugTimer + dt
    if fallParticleDebugTimer > 2.0 then
        fallParticleDebugTimer = 0
        print(string.format("[Particles] onGround=%s jumping=%s alive=%d/%d count=%d",
            tostring(player.isOnGround), tostring(player.isJumping),
            PixelSystem.alivePixels, PixelSystem.totalPixels, #M.fallParticles))
    end

    local isFalling = not player.isOnGround and not player.isJumping
    if isFalling and PixelSystem.alivePixels < PixelSystem.totalPixels then
        local consumeRatio = 1.0 - PixelSystem.alivePixels / math.max(1, PixelSystem.totalPixels)
        local baseRatio = math.max(0.15, consumeRatio)
        local maxParticles = math.floor(4 + baseRatio * 14)
        local spawnChance = 0.40 + baseRatio * 0.50
        local spawnAttempts = 1 + math.floor(baseRatio * 2)

        local playerS = Physics.PlayerGridSize()
        local feetGridY = player.gridY + playerS
        local groundGridY = feetGridY
        for searchY = feetGridY, Config.MAP_ROWS do
            if Physics.IsSolid(player.gridX, searchY) or Physics.IsPlatform(player.gridX, searchY) then
                groundGridY = searchY
                break
            end
            if searchY == Config.MAP_ROWS then
                groundGridY = Config.MAP_ROWS + 1
            end
        end
        local groundY = (groundGridY - 1) * Config.GRID

        for _ = 1, spawnAttempts do
            if math.random() < spawnChance and #M.fallParticles < maxParticles then
                local worldX = (player.gridX - 1) * Config.GRID
                local baseY = (player.gridY - 1) * Config.GRID
                local totalSize = N * ps
                local side = math.random() > 0.5 and 1 or -1
                local emitX = worldX + totalSize * 0.5 + side * (totalSize * 0.3 + math.random() * totalSize * 0.2)
                local emitY = baseY + totalSize * (0.3 + math.random() * 0.5)
                local speedMul = 0.7 + consumeRatio * 0.6
                local life = 1.2 + consumeRatio * 0.6 + math.random() * 0.3
                table.insert(M.fallParticles, {
                    x = emitX, y = emitY,
                    vx = side * (30 + math.random() * 40) * speedMul,
                    vy = -(20 + math.random() * 30) * speedMul,
                    life = life, maxLife = life,
                    size = ps,
                    gravity = 120 + math.random() * 40,
                    colorRow = math.random(5, 10),
                    groundY = groundY,
                    bounces = 0,
                    maxBounces = 1 + math.floor(math.random() * 2),
                })
            end
        end
    end

    -- 更新粒子
    local i = 1
    while i <= #M.fallParticles do
        local p = M.fallParticles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(M.fallParticles, i)
        else
            p.vy = p.vy + p.gravity * dt
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt

            if p.y >= p.groundY and p.vy > 0 then
                if p.bounces < p.maxBounces then
                    p.y = p.groundY
                    p.vy = -p.vy * (0.3 + math.random() * 0.15)
                    p.vx = p.vx * 0.6
                    p.bounces = p.bounces + 1
                else
                    p.y = p.groundY
                    p.vy = 0
                    p.vx = 0
                    p.life = math.min(p.life, 0.3)
                end
            end

            local lifeRatio = p.life / p.maxLife
            if lifeRatio < 0.2 then
                p.size = math.max(1, math.floor(ps * lifeRatio / 0.2 + 0.5))
            end
            i = i + 1
        end
    end
end

-- ====================================================================
-- 起跳像素压缩
-- ====================================================================
M.jumpSquash = {
    active = false,
    frame = 0,
    phase = "none",
}

function M.TriggerJumpSquash()
    M.jumpSquash.active = true
    M.jumpSquash.frame = 0
    M.jumpSquash.phase = "squash"
end

function M.UpdateJumpSquashFrame()
    if not M.jumpSquash.active then return end
    M.jumpSquash.frame = M.jumpSquash.frame + 1

    if M.jumpSquash.phase == "squash" then
        if M.jumpSquash.frame > Config.PLAYER_CONFIG.jumpSquashFrames then
            M.jumpSquash.phase = "stretch"
            M.jumpSquash.frame = 0
        end
    elseif M.jumpSquash.phase == "stretch" then
        if M.jumpSquash.frame > Config.PLAYER_CONFIG.jumpStretchFrames then
            M.jumpSquash.phase = "none"
            M.jumpSquash.active = false
            M.jumpSquash.frame = 0
        end
    end
end

--- 获取跳跃形变对某个像素的偏移
function M.GetJumpSquashForPixel(row, col)
    if not M.jumpSquash.active then return 0, false end
    local N = Config.PLAYER_CONFIG.pixelGridSize
    local cx = (N + 1) / 2
    local colDist = col - cx

    if M.jumpSquash.phase == "squash" then
        local progress = M.jumpSquash.frame / Config.PLAYER_CONFIG.jumpSquashFrames
        local rowWeight = row / N
        local squashAmt = progress * rowWeight * 0.3
        local shift = -math.floor(colDist * squashAmt + 0.5)
        return shift, false
    elseif M.jumpSquash.phase == "stretch" then
        local progress = M.jumpSquash.frame / Config.PLAYER_CONFIG.jumpStretchFrames
        local stretchT = math.sin(progress * math.pi)
        local rowWeight = 1.0 - row / N
        local stretchAmt = stretchT * rowWeight * 0.4
        local shift = math.floor(colDist * stretchAmt + 0.5)
        return shift, false
    end
    return 0, false
end

-- ====================================================================
-- 跳不动抖动
-- ====================================================================
M.cantJumpShake = {
    active = false,
    timer = 0,
}

function M.TriggerCantJumpShake()
    if M.cantJumpShake.active then return end
    M.cantJumpShake.active = true
    M.cantJumpShake.timer = Config.PLAYER_CONFIG.cantJumpShakeDur
end

function M.UpdateCantJumpShake(dt)
    if not M.cantJumpShake.active then return end
    M.cantJumpShake.timer = M.cantJumpShake.timer - dt
    if M.cantJumpShake.timer <= 0 then
        M.cantJumpShake.active = false
        M.cantJumpShake.timer = 0
    end
end

function M.GetCantJumpShakeOffset()
    if not M.cantJumpShake.active then return 0, 0 end
    local PC = Config.PLAYER_CONFIG
    local progress = 1.0 - M.cantJumpShake.timer / PC.cantJumpShakeDur
    local decay = 1.0 - progress
    local freq = 30
    local xOff = math.floor(math.sin(M.cantJumpShake.timer * freq * math.pi * 2) * PC.cantJumpShakeAmp * decay + 0.5)
    local yOff = math.floor(math.cos(M.cantJumpShake.timer * freq * 1.3 * math.pi * 2) * 1 * decay + 0.5)
    return xOff, yOff
end

-- ====================================================================
-- 帧驱动入口
-- ====================================================================

M.FLAME_ANIM_FPS = FLAME_ANIM_FPS

--- 每帧调用的动画更新
function M.Update(dt, gameTime)
    -- 火焰动画帧驱动
    local frameInterval = 1.0 / FLAME_ANIM_FPS
    M.flameAnimTimer = M.flameAnimTimer + dt
    if M.flameAnimTimer >= frameInterval then
        M.flameAnimTimer = M.flameAnimTimer - frameInterval
        M.UpdateFlameAnimFrame()
        M.UpdateJumpSquashFrame()
    end

    -- 连续动画更新
    M.UpdateLanternSway(dt, gameTime)
    M.UpdateFallParticles(dt, gameTime)
    M.UpdateCantJumpShake(dt)
end

--- 重置所有动画状态
function M.Reset()
    M.lanternSway.angle = 0
    M.lanternSway.velocity = 0
    M.lanternSway.active = false
    M.fallParticles = {}
    M.jumpSquash.active = false
    M.jumpSquash.frame = 0
    M.jumpSquash.phase = "none"
    M.cantJumpShake.active = false
    M.cantJumpShake.timer = 0
    M.flameAnimTimer = 0
    M.flameAnimFrame = 0
    M.rowOffsets = {}
    M.rowVOffsets = {}
end

return M
