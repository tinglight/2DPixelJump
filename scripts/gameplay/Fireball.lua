------------------------------------------------------------
-- gameplay/Fireball.lua — 火球发射系统
--
-- 玩家获得能力点后可按 E 发射火球：
-- - 朝玩家当前面朝方向直线飞行
-- - 碰到墙壁(SOLID类)、水面(WATER类)、流水(PIPE区域) → 消失
-- - 命中熄灭灯 → 调用 FogOfWar.IgniteLight 点燃
-- - 命中已点亮灯 + hasLanternDash → 触发灯间位移链
------------------------------------------------------------
local Config = require("gameplay.Config")
local FogOfWar = require("FogOfWar")

local M = {}

-- 依赖（通过 Inject 注入）
local Physics = nil
local PlayerController = nil
local LevelManager = nil
local FlameDashChain = nil

function M.Inject(deps)
    Physics = deps.Physics
    PlayerController = deps.PlayerController
    LevelManager = deps.LevelManager
    FlameDashChain = deps.FlameDashChain
end

-- ====================================================================
-- 配置
-- ====================================================================
local FIREBALL_SPEED = 200     -- 飞行速度 px/s
local FIREBALL_SIZE = 4        -- 碰撞/渲染半径 px
local FIREBALL_LIFE = 3.0      -- 最大存活时间 s
local GRID = Config.GRID

-- ====================================================================
-- 运行时状态
-- ====================================================================
local fireball = nil  -- { x, y, dir, life, trail }  或 nil（无火球飞行中）

-- 吸收动画状态
local absorbAnim = nil  -- { x, y, timer, duration } 或 nil

-- ====================================================================
-- 公开接口
-- ====================================================================

--- 是否有火球正在飞行
function M.IsActive()
    return fireball ~= nil
end

--- 获取火球状态（渲染用）
function M.GetFireball()
    return fireball
end

--- 获取吸收动画状态（渲染用）
function M.GetAbsorbAnim()
    return absorbAnim
end

--- 发射火球
---@param dirX number 水平方向 (-1/0/1)
---@param dirY number 垂直方向 (-1/0/1)，负数=上，正数=下
---@return boolean 是否成功发射
function M.Shoot(dirX, dirY)
    if fireball then return false end  -- 同时只能有一颗火球
    local p = PlayerController.player
    if not p.hasFireball then return false end

    -- 归一化方向（支持对角线）
    local len = math.sqrt(dirX * dirX + dirY * dirY)
    if len < 0.01 then
        -- 没有方向输入时，使用玩家面朝方向（水平）
        dirX = p.facingRight and 1 or -1
        dirY = 0
        len = 1
    end
    local ndx = dirX / len
    local ndy = dirY / len

    local s = Physics.PlayerGridSize()
    -- 火球从玩家中心发出
    local startX = (p.gridX - 1) * GRID + s * GRID * 0.5
    local startY = (p.gridY - 1) * GRID + s * GRID * 0.5

    fireball = {
        x = startX,
        y = startY,
        dx = ndx,   -- 归一化方向 X
        dy = ndy,   -- 归一化方向 Y
        life = FIREBALL_LIFE,
        trail = {},  -- 尾迹粒子 { {x,y,alpha}, ... }
    }
    return true
end

--- 开始吸收动画（能力点被拾取时调用）
---@param worldX number 能力点世界X坐标
---@param worldY number 能力点世界Y坐标
function M.StartAbsorbAnim(worldX, worldY)
    absorbAnim = {
        x = worldX,
        y = worldY,
        timer = 0,
        duration = 0.6,
    }
end

--- 每帧更新
---@param dt number
function M.Update(dt)
    -- 更新吸收动画
    if absorbAnim then
        absorbAnim.timer = absorbAnim.timer + dt
        if absorbAnim.timer >= absorbAnim.duration then
            absorbAnim = nil
        end
    end

    -- 更新火球飞行
    if not fireball then return end

    fireball.life = fireball.life - dt
    if fireball.life <= 0 then
        fireball = nil
        return
    end

    -- 移动（直线，2D 方向）
    local moveX = FIREBALL_SPEED * fireball.dx * dt
    local moveY = FIREBALL_SPEED * fireball.dy * dt
    fireball.x = fireball.x + moveX
    fireball.y = fireball.y + moveY

    -- 添加尾迹粒子（存储相对于当前火球位置的偏移，避免相机移动导致曲线效果）
    -- 先更新旧粒子偏移（因为火球移动了，旧粒子距离更远）
    for i, t in ipairs(fireball.trail) do
        t.offX = t.offX - moveX
        t.offY = t.offY - moveY
        t.alpha = t.alpha - dt * 4
    end
    table.insert(fireball.trail, 1, { offX = 0, offY = 0, alpha = 1.0 })
    if #fireball.trail > 8 then
        table.remove(fireball.trail)
    end

    -- 碰撞检测：转换为格子坐标
    local col = math.floor(fireball.x / GRID) + 1
    local row = math.floor(fireball.y / GRID) + 1

    -- 超出地图边界
    if col < 1 or col > Config.MAP_COLS or row < 1 or row > Config.MAP_ROWS then
        fireball = nil
        return
    end

    -- 优先检查是否命中灯（灯可能嵌在墙里，必须在墙碰撞之前检测）
    local lights = FogOfWar.GetLightSources()
    for _, light in ipairs(lights) do
        -- 灯的位置（格子坐标中心）
        local lampX = (light.col - 1) * GRID + GRID * 0.5
        local lampY = (light.row - 1) * GRID + GRID * 0.5
        local dx = fireball.x - lampX
        local dy = fireball.y - lampY
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist < GRID * 0.8 then
            if light.extinguished then
                -- 命中熄灭灯 → 点燃并解锁 lanternDash
                FogOfWar.IgniteLight(light.col, light.row)
                PlayerController.player.hasLanternDash = true
                fireball = nil
                return
            else
                -- 命中已点亮灯 → 如果有 lanternDash 则触发灯间位移
                if PlayerController.player.hasLanternDash and FlameDashChain then
                    fireball = nil
                    local player = PlayerController.player
                    local ctx = {
                        gridX = player.gridX,
                        gridY = player.gridY,
                        gridSize = Config.PLAYER_CONFIG.playerGridSize or 2,
                        mapRows = Config.MAP_ROWS,
                        forceLamp = light,  -- 命中的灯直接作为第一个跃迁目标
                        isBodyBlocked = function(gx, gy)
                            return Physics.PlayerCollidesAt(gx, gy)
                        end,
                    }
                    FlameDashChain.TryTrigger(ctx)
                    return
                end
                -- 没有 lanternDash，火球穿过已亮灯（不消失）
            end
        end
    end

    -- 然后检查碰到的 tile（墙壁/水面等）
    if LevelManager.levelData and LevelManager.levelData[row] then
        local val = LevelManager.levelData[row][col]
        local base, _ = Physics.GetTileType(val)
        local TILE = LevelManager.TILE

        -- 碰到墙面（所有实体类 tile）
        if base == TILE.SOLID or base == TILE.SOLID_PILLAR or base == TILE.SOLID_SEWER
            or base == TILE.SLOPE_TR or base == TILE.SLOPE_TL
            or base == TILE.SLOPE_BR or base == TILE.SLOPE_BL then
            fireball = nil
            return
        end

        -- 碰到水面/流水
        if base == TILE.WATER or base == TILE.POISON_WATER or base == TILE.BLACK_WATER
            or base == TILE.PIPE then
            fireball = nil
            return
        end
    end
end

--- 重置状态（关卡切换/死亡时调用）
function M.Reset()
    fireball = nil
    absorbAnim = nil
end

return M
