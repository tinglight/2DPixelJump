------------------------------------------------------------
-- gameplay/Renderer.lua — 渲染系统（背景、网格、地图、角色、HUD）
------------------------------------------------------------
local Config = require("gameplay.Config")
local GAME_VERSION = require("version")
local SolidRenderer = require("SolidRenderer")
local EditorConstants = require("editor.Constants")

local M = {}

-- ====================================================================
-- 像素字体定义 (5x7 pixel font)
-- ====================================================================
local PIXEL_FONT = {
    A = {
        {0,1,1,1,0},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,1,1,1,1},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,0,0,0,1},
    },
    B = {
        {1,1,1,1,0},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,1,1,1,0},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,1,1,1,0},
    },
    D = {
        {1,1,1,1,0},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,1,1,1,0},
    },
    E = {
        {1,1,1,1,1},
        {1,0,0,0,0},
        {1,0,0,0,0},
        {1,1,1,1,0},
        {1,0,0,0,0},
        {1,0,0,0,0},
        {1,1,1,1,1},
    },
    F = {
        {1,1,1,1,1},
        {1,0,0,0,0},
        {1,0,0,0,0},
        {1,1,1,1,0},
        {1,0,0,0,0},
        {1,0,0,0,0},
        {1,0,0,0,0},
    },
    I = {
        {1,1,1,1,1},
        {0,0,1,0,0},
        {0,0,1,0,0},
        {0,0,1,0,0},
        {0,0,1,0,0},
        {0,0,1,0,0},
        {1,1,1,1,1},
    },
    L = {
        {1,0,0,0,0},
        {1,0,0,0,0},
        {1,0,0,0,0},
        {1,0,0,0,0},
        {1,0,0,0,0},
        {1,0,0,0,0},
        {1,1,1,1,1},
    },
    N = {
        {1,0,0,0,1},
        {1,1,0,0,1},
        {1,0,1,0,1},
        {1,0,1,0,1},
        {1,0,0,1,1},
        {1,0,0,1,1},
        {1,0,0,0,1},
    },
    O = {
        {0,1,1,1,0},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {0,1,1,1,0},
    },
    R = {
        {1,1,1,1,0},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,1,1,1,0},
        {1,0,1,0,0},
        {1,0,0,1,0},
        {1,0,0,0,1},
    },
    T = {
        {1,1,1,1,1},
        {0,0,1,0,0},
        {0,0,1,0,0},
        {0,0,1,0,0},
        {0,0,1,0,0},
        {0,0,1,0,0},
        {0,0,1,0,0},
    },
    U = {
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {1,0,0,0,1},
        {0,1,1,1,0},
    },
    Y = {
        {1,0,0,0,1},
        {1,0,0,0,1},
        {0,1,0,1,0},
        {0,0,1,0,0},
        {0,0,1,0,0},
        {0,0,1,0,0},
        {0,0,1,0,0},
    },
    [" "] = {
        {0,0,0,0,0},
        {0,0,0,0,0},
        {0,0,0,0,0},
        {0,0,0,0,0},
        {0,0,0,0,0},
        {0,0,0,0,0},
        {0,0,0,0,0},
    },
}

--- 绘制像素风格文字（居中）
---@param text string 要绘制的文本（大写）
---@param centerX number 中心X
---@param centerY number 中心Y
---@param pixelSize number 每个像素块尺寸
---@param r number 红色 0-255
---@param g number 绿色 0-255
---@param b number 蓝色 0-255
---@param alpha number 透明度 0-255
function M.DrawPixelText(text, centerX, centerY, pixelSize, r, g, b, alpha)
    local vg = M.vg
    local charW = 5   -- 每字符宽度（像素格）
    local charH = 7   -- 每字符高度（像素格）
    local spacing = 1 -- 字符间隔（像素格）

    local totalW = #text * (charW + spacing) - spacing
    local startX = centerX - (totalW * pixelSize) / 2
    local startY = centerY - (charH * pixelSize) / 2

    for ci = 1, #text do
        local ch = text:sub(ci, ci)
        local glyph = PIXEL_FONT[ch]
        if glyph then
            local charStartX = startX + (ci - 1) * (charW + spacing) * pixelSize
            for row = 1, charH do
                for col = 1, charW do
                    if glyph[row][col] == 1 then
                        local px = charStartX + (col - 1) * pixelSize
                        local py = startY + (row - 1) * pixelSize
                        nvgBeginPath(vg)
                        nvgRect(vg, px, py, pixelSize, pixelSize)
                        nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
                        nvgFill(vg)
                    end
                end
            end
        end
    end
end

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

function M.UpdateBonfireMessage(dt)
    if M.bonfireMessage.active then
        M.bonfireMessage.timer = M.bonfireMessage.timer + dt
        if M.bonfireMessage.timer >= M.bonfireMessage.duration then
            M.bonfireMessage.active = false
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

    -- 设置碰撞检测器用于光照阴影遮挡
    SolidRenderer.SetCollisionChecker(function(col, row)
        return Physics.IsSolidForLight(col, row)
    end)
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
local bgImageHandle_ = nil
local bgImagePath_ = ""

function M.DrawBackground()
    local vg = M.vg

    -- 默认渐变背景
    local bg = nvgLinearGradient(vg, 0, 0, 0, M.screenDesignH,
        nvgRGBA(10, 5, 20, 255), nvgRGBA(30, 15, 40, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, M.screenDesignW, M.screenDesignH)
    nvgFillPaint(vg, bg)
    nvgFill(vg)

    -- 背景图铺满整个地图区域
    if Config.backgroundImage ~= "" then
        -- 路径变化时重新加载
        if bgImagePath_ ~= Config.backgroundImage then
            bgImageHandle_ = nvgCreateImage(vg, Config.backgroundImage, 0)
            bgImagePath_ = Config.backgroundImage
        end
        if bgImageHandle_ and bgImageHandle_ > 0 then
            local GRID = Config.GRID
            local mapW = Config.MAP_COLS * GRID
            local mapH = Config.MAP_ROWS * GRID
            local drawX = -M.cameraX
            local drawY = 0
            local imgPaint = nvgImagePattern(vg, drawX, drawY, mapW, mapH, 0, bgImageHandle_, Config.bgImageAlpha or 0.5)
            nvgBeginPath(vg)
            nvgRect(vg, drawX, drawY, mapW, mapH)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        end
    else
        bgImageHandle_ = nil
        bgImagePath_ = ""
    end
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

-- 检查某格是否为实体方块（用于邻居检测）
local function IsSolidAt(row, col)
    if row < 1 or row > Config.MAP_ROWS or col < 1 or col > Config.MAP_COLS then
        return false
    end
    local val = LevelManager.levelData[row][col]
    if not val or val == 0 then return false end
    local base = Physics.GetTileType(val)
    return base == 1 or base == 13 or base == 17  -- SOLID or SOLID_PILLAR or SOLID_SEWER
end

-- 检查某格是否为柱子（专门用于柱子拼接检测）
local function IsPillarAt(row, col)
    if row < 1 or row > Config.MAP_ROWS or col < 1 or col > Config.MAP_COLS then
        return false
    end
    local val = LevelManager.levelData[row][col]
    if not val or val == 0 then return false end
    local base = Physics.GetTileType(val)
    return base == 13  -- SOLID_PILLAR only
end

-- 检查某格是否为水体（用于下水道水边衔接检测）
local function IsWaterAt(row, col)
    if row < 1 or row > Config.MAP_ROWS or col < 1 or col > Config.MAP_COLS then
        return false
    end
    local val = LevelManager.levelData[row][col]
    if not val or val == 0 then return false end
    local base = Physics.GetTileType(val)
    return base == 9 or base == 10 or base == 11  -- WATER, POISON_WATER, BLACK_WATER
end

function M.DrawMap()
    local vg = M.vg
    local GRID = Config.GRID
    local TILE = LevelManager.TILE
    -- 传入动画时间驱动萤火虫闪烁
    SolidRenderer.SetTime(M.gameTime)
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

            if base == TILE.SOLID or base == TILE.SOLID_PILLAR or base == TILE.SOLID_SEWER then
                -- 计算玩家光源对该格子的光照
                local player = PlayerController.player
                local flameRatio = PixelSystem.alivePixels / math.max(1, PixelSystem.totalPixels)
                local playerLightRadius = Config.PLAYER_CONFIG.defaultLightDiameter * 0.5 * flameRatio
                local pLit, pLdx, pLdy = SolidRenderer.CalcPlayerLightDirection(
                    col, row, player.gridX, player.gridY + 1, playerLightRadius)

                -- 检查激活的篝火光源
                local bLit, bLdx, bLdy = 0, 0, 0
                for cpKey, activated in pairs(LevelManager.checkpointActivated) do
                    if activated then
                        local cpRow, cpCol = cpKey:match("(%d+)_(%d+)")
                        cpRow, cpCol = tonumber(cpRow), tonumber(cpCol)
                        if cpRow and cpCol then
                            local lit2, ldx2, ldy2 = SolidRenderer.CalcPlayerLightDirection(
                                col, row, cpCol, cpRow, 4)
                            if lit2 > bLit then
                                bLit, bLdx, bLdy = lit2, ldx2, ldy2
                            end
                        end
                    end
                end

                -- 合并所有光源
                local totalLit = math.min(1.0, pLit + bLit)
                local totalLdx = pLdx * pLit + bLdx * bLit
                local totalLdy = pLdy * pLit + bLdy * bLit
                local len = math.sqrt(totalLdx * totalLdx + totalLdy * totalLdy)
                if len > 0.01 then
                    totalLdx = totalLdx / len
                    totalLdy = totalLdy / len
                end

                -- 检测四邻是否有实体方块（用于青苔边缘）
                local neighbors = {
                    top    = IsSolidAt(row - 1, col),
                    bottom = IsSolidAt(row + 1, col),
                    left   = IsSolidAt(row, col - 1),
                    right  = IsSolidAt(row, col + 1),
                    -- 柱子拼接专用邻居检测
                    pillarTop    = IsPillarAt(row - 1, col),
                    pillarBottom = IsPillarAt(row + 1, col),
                    pillarLeft   = IsPillarAt(row, col - 1),
                    pillarRight  = IsPillarAt(row, col + 1),
                }
                -- 下水道瓦片额外检测：对角邻居 + 水体邻接
                if base == 17 then  -- SOLID_SEWER
                    neighbors.topLeft     = IsSolidAt(row - 1, col - 1)
                    neighbors.topRight    = IsSolidAt(row - 1, col + 1)
                    neighbors.bottomLeft  = IsSolidAt(row + 1, col - 1)
                    neighbors.bottomRight = IsSolidAt(row + 1, col + 1)
                    neighbors.water = IsWaterAt(row + 1, col) or IsWaterAt(row, col - 1) or IsWaterAt(row, col + 1)
                end

                SolidRenderer.DrawSolid(vg, base, px, py, GRID, totalLit, totalLdx, totalLdy, col, row, neighbors)

            elseif base == TILE.SPAWN then
                nvgBeginPath(vg)
                nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.5, 6)
                nvgFillColor(vg, nvgRGBA(255, 200, 50, 40))
                nvgFill(vg)

            elseif base == TILE.FUEL then
                local key = row .. "_" .. col
                if not LevelManager.collectedItems[key] then
                    M.DrawFuelPixelFlame(px, py, col, row)
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
                    -- 隐藏墙未揭示时渲染为砖块样式（与 SOLID 相同外观）
                    local player = PlayerController.player
                    local flameRatio = PixelSystem.alivePixels / math.max(1, PixelSystem.totalPixels)
                    local playerLightRadius = Config.PLAYER_CONFIG.defaultLightDiameter * 0.5 * flameRatio
                    local pLit, pLdx, pLdy = SolidRenderer.CalcPlayerLightDirection(
                        col, row, player.gridX, player.gridY + 1, playerLightRadius)
                    local neighbors = {
                        top    = IsSolidAt(row - 1, col),
                        bottom = IsSolidAt(row + 1, col),
                        left   = IsSolidAt(row, col - 1),
                        right  = IsSolidAt(row, col + 1),
                    }
                    SolidRenderer.DrawSolid(vg, TILE.SOLID, px, py, GRID, pLit, pLdx, pLdy, col, row, neighbors)
                end

            elseif base == TILE.CHECKPOINT then
                M.DrawCheckpointTile(px, py, row, col)
            end

            ::continueTile::
        end
    end
end

-- ====================================================================
-- 篝火 (CHECKPOINT) 渲染
-- ====================================================================
function M.DrawCheckpointTile(px, py, row, col)
    local vg = M.vg
    local GRID = Config.GRID
    local key = row .. "_" .. col
    local activated = LevelManager.checkpointActivated[key]
    local ps = 2  -- 像素块大小

    -- 石头底座
    local stones = {
        {3, 6}, {4, 6}, {5, 6}, {6, 6},
        {2, 5}, {3, 5}, {6, 5}, {7, 5},
        {4, 5}, {5, 5},
    }
    for _, s in ipairs(stones) do
        local sx = px + s[1] * ps
        local sy = py + s[2] * ps
        nvgBeginPath(vg)
        nvgRect(vg, sx, sy, ps, ps)
        if s[2] == 6 then
            nvgFillColor(vg, nvgRGBA(60, 55, 50, 255))
        else
            nvgFillColor(vg, nvgRGBA(80, 75, 65, 255))
        end
        nvgFill(vg)
    end

    -- 木头
    local logs = {
        {3, 4}, {4, 4}, {5, 4}, {6, 4},
        {4, 3}, {5, 3},
    }
    for _, l in ipairs(logs) do
        local lx = px + l[1] * ps
        local ly = py + l[2] * ps
        nvgBeginPath(vg)
        nvgRect(vg, lx, ly, ps, ps)
        nvgFillColor(vg, nvgRGBA(100, 60, 25, 255))
        nvgFill(vg)
    end

    if activated then
        -- 点燃状态：像素火焰
        local t = M.gameTime
        local flicker1 = math.sin(t * 8 + col * 2.1) * 0.5 + 0.5
        local flicker2 = math.sin(t * 11 + row * 1.7) * 0.5 + 0.5

        local flames = {
            {3, 3, {255, 100, 10}}, {4, 3, {255, 130, 20}}, {5, 3, {255, 100, 10}}, {6, 3, {255, 120, 15}},
            {4, 2, {255, 180, 30}}, {5, 2, {255, 160, 20}},
            {3, 2, {255, 120, 10}}, {6, 2, {255, 130, 15}},
            {4, 1, {255, 220, 80}}, {5, 1, {255, 200, 60}},
        }
        for _, f in ipairs(flames) do
            local fx = px + f[1] * ps
            local fy = py + f[2] * ps
            local c = f[3]
            local flick = (f[2] <= 1) and flicker1 or flicker2
            local a = math.floor(180 + 75 * flick)
            nvgBeginPath(vg)
            nvgRect(vg, fx, fy, ps, ps)
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], a))
            nvgFill(vg)
        end

        -- 火焰光晕
        local glowA = math.floor(20 + 15 * flicker1)
        nvgBeginPath(vg)
        nvgCircle(vg, px + GRID * 0.5, py + GRID * 0.3, 8)
        nvgFillColor(vg, nvgRGBA(255, 150, 30, glowA))
        nvgFill(vg)
    else
        -- 未点燃：暗灰余烬
        local embers = {
            {4, 3}, {5, 3},
        }
        for _, e in ipairs(embers) do
            local ex = px + e[1] * ps
            local ey = py + e[2] * ps
            nvgBeginPath(vg)
            nvgRect(vg, ex, ey, ps, ps)
            nvgFillColor(vg, nvgRGBA(80, 40, 20, 150))
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
        -- 半透明黑色遮罩
        nvgBeginPath(vg)
        nvgRect(vg, 0, 22, M.screenDesignW, M.screenDesignH - 22)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
        nvgFill(vg)
        -- 像素风格 "YOU DIE"
        M.DrawPixelText("YOU DIE", M.screenDesignW * 0.5, M.screenDesignH * 0.4, 4, 255, 60, 60, 255)
        -- 提示文字
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, M.screenDesignW * 0.5, M.screenDesignH * 0.58, "R:Retry  N:New Level")
    elseif M.gameState == Config.STATE_WIN then
        -- 半透明黑色遮罩
        nvgBeginPath(vg)
        nvgRect(vg, 0, 22, M.screenDesignW, M.screenDesignH - 22)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
        nvgFill(vg)
        -- 像素风格 "YOU WIN"（需要添加 W 字符）
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
        nvgText(vg, M.screenDesignW * 0.5, M.screenDesignH * 0.4, "FLAME ETERNAL!")
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, M.screenDesignW * 0.5, M.screenDesignH * 0.55, "N:Next Level  R:Replay")
    end

    -- BONFIRE LIT 消息
    if M.bonfireMessage.active then
        local t = M.bonfireMessage.timer
        local dur = M.bonfireMessage.duration
        -- 淡入淡出
        local alpha = 255
        if t < 0.4 then
            alpha = math.floor(t / 0.4 * 255)
        elseif t > dur - 0.6 then
            alpha = math.floor((dur - t) / 0.6 * 255)
        end
        alpha = math.max(0, math.min(255, alpha))
        -- 像素风格 "BONFIRE LIT" 居中偏上
        M.DrawPixelText("BONFIRE LIT", M.screenDesignW * 0.5, M.screenDesignH * 0.35, 3, 255, 180, 40, alpha)
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

-- ====================================================================
-- 装饰物渲染
-- ====================================================================
local gameDecoImageCache = {}  -- { [spritePath] = nvgImageHandle }

function M.DrawDecorations()
    if not LevelManager.decorations or #LevelManager.decorations == 0 then return end

    local vg = M.vg
    local GRID = Config.GRID
    local DECO_TYPES = EditorConstants.DECORATION_TYPES
    local startCol = math.max(1, math.floor(M.cameraX / GRID) + 1)
    local visW = Config.DESIGN_W * (Config.PLAYER_CONFIG.cameraZoom or 1.0)
    local endCol = math.min(Config.MAP_COLS, startCol + math.ceil(visW / GRID) + 2)

    for _, deco in ipairs(LevelManager.decorations) do
        if deco.col >= startCol and deco.col <= endCol then
            local decoType = DECO_TYPES[deco.typeId]
            if not decoType then goto continueDeco end

            local px = (deco.col - 1) * GRID - M.cameraX
            local py = (deco.row - 1) * GRID

            if decoType.sprite and decoType.size then
                local sizeW = decoType.size.w or 1
                local sizeH = decoType.size.h or 1
                local drawW = sizeW * GRID
                local drawH = sizeH * GRID
                -- 锚点在中心：放置格的中心 = 装饰物图片的中心
                local imgX = px + GRID * 0.5 - drawW * 0.5
                local imgY = py + GRID * 0.5 - drawH * 0.5

                -- 加载/缓存贴图
                if not gameDecoImageCache[decoType.sprite] then
                    local handle = nvgCreateImage(vg, decoType.sprite, 0)
                    gameDecoImageCache[decoType.sprite] = handle or -1
                end

                local imgHandle = gameDecoImageCache[decoType.sprite]
                if imgHandle and imgHandle > 0 then
                    local paint = nvgImagePattern(vg, imgX, imgY, drawW, drawH, 0, imgHandle, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, imgX, imgY, drawW, drawH)
                    nvgFillPaint(vg, paint)
                    nvgFill(vg)
                end
            else
                -- 无贴图 fallback
                local color = decoType.color or {180, 140, 220}
                nvgBeginPath(vg)
                nvgRect(vg, px, py, GRID, GRID)
                nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 150))
                nvgFill(vg)
            end

            ::continueDeco::
        end
    end
end

return M
