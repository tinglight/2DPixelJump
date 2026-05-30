------------------------------------------------------------
-- CrossLevel.lua — 跨关卡交互系统
-- 负责：飞行道具管理、边界穿越模拟、跨关卡开关状态
------------------------------------------------------------
local C = require("editor.Constants")
local S = require("editor.State")
local TileUtils = require("editor.TileUtils")

local M = {}

-- 依赖注入
local CloudStorage, WorldMapEditor, cjson

---@param deps table { CloudStorage, WorldMapEditor, cjson }
function M.Inject(deps)
    CloudStorage = deps.CloudStorage
    WorldMapEditor = deps.WorldMapEditor
    cjson = deps.cjson
end

------------------------------------------------------------
-- 道具发射
------------------------------------------------------------

--- 从玩家位置发射火球
function M.LaunchProjectile(gridX, gridY, facingRight)
    local playerSize = C.FLAME_CFG.pixelGridSize * C.FLAME_CFG.pixelSize
    local centerX = (gridX - 1) * C.GRID + playerSize * 0.5
    local centerY = (gridY - 1) * C.GRID + playerSize * 0.5
    local dir = facingRight and 1 or -1
    -- 从角色前方偏移发射
    local spawnX = centerX + dir * (playerSize * 0.5 + 4)
    local spawnY = centerY - 2

    table.insert(S.projectiles, {
        x = spawnX,
        y = spawnY,
        vx = C.PROJECTILE_SPEED * dir,
        vy = 0,
        life = C.PROJECTILE_LIFE,
    })
end

------------------------------------------------------------
-- 道具更新
------------------------------------------------------------

function M.Update(dt)
    if S.editorMode ~= C.MODE_WORLDPLAY and S.editorMode ~= C.MODE_PLAY then
        return
    end
    -- 冷却更新
    if S.worldPlayCooldown and S.worldPlayCooldown > 0 then
        S.worldPlayCooldown = S.worldPlayCooldown - dt
    end

    local i = 1
    while i <= #S.projectiles do
        local proj = S.projectiles[i]
        local removed = M.UpdateOneProjectile(proj, dt)
        if removed then
            table.remove(S.projectiles, i)
        else
            i = i + 1
        end
    end
end

--- 更新单个道具，返回 true 表示应移除
function M.UpdateOneProjectile(proj, dt)
    -- 生命衰减
    proj.life = proj.life - dt
    if proj.life <= 0 then return true end

    -- 物理移动
    proj.vy = proj.vy + C.PROJECTILE_GRAVITY * dt
    proj.x = proj.x + proj.vx * dt
    proj.y = proj.y + proj.vy * dt

    -- 上下越界检测
    if proj.y < 0 or proj.y > S.MAP_ROWS * C.GRID then
        return true
    end

    -- 当前关卡内碰撞检测
    local col = math.floor(proj.x / C.GRID) + 1
    local row = math.floor(proj.y / C.GRID) + 1
    if col >= 1 and col <= S.MAP_COLS and row >= 1 and row <= S.MAP_ROWS then
        local val = S.levelData[row][col]
        local base, group = TileUtils.GetTileType(val)
        if base == C.TILE.SOLID or base == C.TILE.SOLID_PILLAR then
            return true  -- 碰墙消失
        elseif base == C.TILE.GATE and not S.play.switchState[group] then
            return true  -- 碰关闭的门消失
        elseif base == C.TILE.SWITCH then
            -- 命中开关：触发
            local key = row .. "_" .. col
            if not S.play.collected[key] then
                S.play.collected[key] = true
                S.play.switchState[group] = not S.play.switchState[group]
                -- 同时记录到跨关卡状态
                if S.worldPlayCurrentFile then
                    M.ActivateCrossSwitch(S.worldPlayCurrentFile, group)
                end
            end
            return true
        end
    end

    -- 边界穿越检测（仅世界试玩模式）
    if S.editorMode == C.MODE_WORLDPLAY then
        local crossed = M.CheckBoundaryCross(proj)
        if crossed then return true end
    end

    return false
end

------------------------------------------------------------
-- 边界穿越
------------------------------------------------------------

function M.CheckBoundaryCross(proj)
    local leftBoundPx = (S.camBound.left - 1) * C.GRID
    local rightBoundPx = S.camBound.right * C.GRID

    local direction = nil
    local overflow = 0

    if proj.x >= rightBoundPx then
        direction = "right"
        overflow = proj.x - rightBoundPx
    elseif proj.x < leftBoundPx then
        direction = "left"
        overflow = leftBoundPx - proj.x
    end

    if not direction then return false end

    -- 查找相邻关卡
    local targetFile = M.FindConnection(direction)
    if not targetFile then return true end  -- 无连接，道具消失

    -- 在目标关卡中模拟飞行
    M.SimulateInNeighbor(proj, targetFile, direction, overflow)
    return true
end

--- 通过世界地图连接图查找方向对应的相邻关卡
function M.FindConnection(direction)
    if not S.worldPlayData or not S.worldPlayCurrentFile then return nil end
    local currentNodeId = nil
    for _, node in ipairs(S.worldPlayData.nodes) do
        if node.file == S.worldPlayCurrentFile then
            currentNodeId = node.id
            break
        end
    end
    if not currentNodeId then return nil end
    for _, conn in ipairs(S.worldPlayData.connections) do
        if conn.fromId == currentNodeId and conn.direction == direction then
            for _, node in ipairs(S.worldPlayData.nodes) do
                if node.id == conn.toId then return node.file end
            end
        end
    end
    return nil
end

--- 在目标关卡中模拟道具飞行路径，检测碰撞
function M.SimulateInNeighbor(proj, targetFile, direction, overflow)
    -- 加载目标关卡数据（只读，不影响当前levelData）
    local json = CloudStorage.Load(targetFile)
    if not json then return end
    local ok, data = pcall(cjson.decode, json)
    if not ok or not data then return end

    -- 解析目标关卡的tile数据
    local targetCols = data.cols or C.DEFAULT_MAP_COLS
    local targetRows = data.rows or C.DEFAULT_MAP_ROWS
    local targetTiles = {}  -- [row][col] = value
    for row = 1, targetRows do
        targetTiles[row] = {}
        for col = 1, targetCols do
            targetTiles[row][col] = C.TILE.EMPTY
        end
    end
    if data.tiles then
        for _, t in ipairs(data.tiles) do
            if t.row >= 1 and t.row <= targetRows and t.col >= 1 and t.col <= targetCols then
                targetTiles[t.row][t.col] = t.v
            end
        end
    end

    -- 获取目标关卡的camBound
    local tBound = data.camBound or { left = 1, top = 1, right = targetCols, bottom = targetRows }

    -- 计算道具在目标关卡的入口位置
    local entryX, entryY
    local projRow = math.floor(proj.y / C.GRID) + 1  -- 保持Y坐标行
    if direction == "right" then
        entryX = (tBound.left - 1) * C.GRID + overflow
        entryY = proj.y
    elseif direction == "left" then
        entryX = tBound.right * C.GRID - overflow
        entryY = proj.y
    else
        return  -- 上下方向暂不处理道具穿越
    end

    -- 模拟飞行路径：从入口位置逐格检测
    local simX = entryX
    local simY = entryY
    local simVx = proj.vx
    local simVy = proj.vy
    local simDt = 1.0 / 60.0  -- 模拟步长
    local maxSteps = math.floor(C.PROJECTILE_LIFE / simDt)
    -- 限制最大模拟步数避免卡顿
    maxSteps = math.min(maxSteps, 300)

    for _ = 1, maxSteps do
        simVy = simVy + C.PROJECTILE_GRAVITY * simDt
        simX = simX + simVx * simDt
        simY = simY + simVy * simDt

        -- 越界退出
        if simX < (tBound.left - 1) * C.GRID or simX > tBound.right * C.GRID then
            break
        end
        if simY < 0 or simY > targetRows * C.GRID then
            break
        end

        local col = math.floor(simX / C.GRID) + 1
        local row = math.floor(simY / C.GRID) + 1
        if col >= 1 and col <= targetCols and row >= 1 and row <= targetRows then
            local val = targetTiles[row][col]
            local base, group = TileUtils.GetTileType(val)
            if base == C.TILE.SOLID or base == C.TILE.SOLID_PILLAR then
                break  -- 碰墙，道具消失
            elseif base == C.TILE.SWITCH then
                -- 命中开关！激活跨关卡开关
                M.ActivateCrossSwitch(targetFile, group)
                S.SetMessage("跨关卡触发: " .. targetFile .. " 组" .. group, 2.0)
                break
            elseif base == C.TILE.GATE then
                -- 碰到关闭的门（检查是否已被跨关卡开关打开）
                local opened = S.crossSwitchState[targetFile] and S.crossSwitchState[targetFile][group]
                if not opened then
                    break  -- 碰关闭的门，消失
                end
            end
        end
    end
end

------------------------------------------------------------
-- 跨关卡开关状态管理
------------------------------------------------------------

--- 记录跨关卡开关激活
function M.ActivateCrossSwitch(filename, group)
    if not S.crossSwitchState[filename] then
        S.crossSwitchState[filename] = {}
    end
    -- toggle 逻辑：与游戏内开关行为一致
    S.crossSwitchState[filename][group] = not S.crossSwitchState[filename][group]
    -- 如果 toggle 回 false，则移除记录
    if not S.crossSwitchState[filename][group] then
        S.crossSwitchState[filename][group] = nil
    end
end

--- 加载关卡时，将跨关卡已激活的开关应用到当前 play 状态
function M.ApplyCrossSwitches(filename)
    if not S.crossSwitchState[filename] then return end
    for group, activated in pairs(S.crossSwitchState[filename]) do
        if activated then
            S.play.switchState[group] = true
        end
    end
end

------------------------------------------------------------
-- 渲染
------------------------------------------------------------

function M.Draw(vg, cameraX, cameraY)
    cameraY = cameraY or 0
    for _, proj in ipairs(S.projectiles) do
        local screenX = proj.x - cameraX
        local screenY = proj.y - cameraY
        -- 发光核心
        nvgBeginPath(vg)
        nvgCircle(vg, screenX, screenY, C.PROJECTILE_SIZE)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
        nvgFill(vg)
        -- 外圈光晕
        nvgBeginPath(vg)
        nvgCircle(vg, screenX, screenY, C.PROJECTILE_SIZE * 2.2)
        nvgFillColor(vg, nvgRGBA(255, 150, 30, 60))
        nvgFill(vg)
        -- 小尾巴（反方向拖尾）
        local tailLen = 8
        local tailDir = proj.vx > 0 and -1 or 1
        nvgBeginPath(vg)
        nvgMoveTo(vg, screenX, screenY - 2)
        nvgLineTo(vg, screenX + tailDir * tailLen, screenY)
        nvgLineTo(vg, screenX, screenY + 2)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 100, 0, 150))
        nvgFill(vg)
    end
end

------------------------------------------------------------
-- 清理
------------------------------------------------------------

--- 切换关卡时清空道具（保留 crossSwitchState）
function M.Clear()
    S.projectiles = {}
end

--- 退出世界试玩时完全重置
function M.Reset()
    S.projectiles = {}
    S.crossSwitchState = {}
end

return M
