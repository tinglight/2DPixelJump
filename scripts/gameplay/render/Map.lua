------------------------------------------------------------
-- gameplay/render/Map.lua — 地图瓦片渲染（光照、实体、各类方块）
------------------------------------------------------------
local Config = require("gameplay.Config")
local SolidRenderer = require("rendering.SolidRenderer")
local CurtainRenderer = require("rendering.CurtainRenderer")

local Map = {}

function Map.Attach(M)
    -- 持久化光照缓存（只在玩家整格位移或篝火状态变化时清空）
    local frameLightCache = {}     -- [row*10000+col] = {lit, ldx, ldy}
    local cachedCampfires = {}     -- 预解析的篝火位置列表 {row, col}
    local lastPlayerGridCol = -1   -- 上次计算光照时的玩家整格列
    local lastPlayerGridRow = -1   -- 上次计算光照时的玩家整格行
    local lastCampfireCount = -1   -- 上次篝火数量（用于检测变化）
    local lastFlameRatioQuant = -1 -- 上次火焰比量化值（避免每帧微变触发重算）

    -- 检查某格是否为实体方块（用于邻居检测，包含未完全消失的隐藏墙）
    local function IsSolidAt(row, col)
        if row < 1 or row > Config.MAP_ROWS or col < 1 or col > Config.MAP_COLS then
            return false
        end
        local LevelManager = M._LevelManager
        local Physics = M._Physics
        local val = LevelManager.levelData[row][col]
        if not val or val == 0 then return false end
        local base, group = Physics.GetTileType(val)
        if base == 1 or base == 13 or base == 17 then  -- SOLID or SOLID_PILLAR or SOLID_SEWER
            return true
        end
        if base >= 19 and base <= 22 then  -- SLOPE_TR/TL/BR/BL
            return true
        end
        -- 隐藏墙：未揭示或正在渐变中也算实体（用于法线计算）
        if base == 8 then  -- HIDDEN_WALL
            local revealTime = LevelManager.hiddenWallRevealed[group]
            if not revealTime then
                return true  -- 未揭示
            end
            local elapsed = M.gameTime - revealTime
            if elapsed < LevelManager.HIDDEN_WALL_FADE_DURATION then
                return true  -- 渐变中
            end
        end
        return false
    end

    -- 检查某格是否为柱子（专门用于柱子拼接检测）
    local function IsPillarAt(row, col)
        if row < 1 or row > Config.MAP_ROWS or col < 1 or col > Config.MAP_COLS then
            return false
        end
        local LevelManager = M._LevelManager
        local Physics = M._Physics
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
        local LevelManager = M._LevelManager
        local Physics = M._Physics
        local val = LevelManager.levelData[row][col]
        if not val or val == 0 then return false end
        local base = Physics.GetTileType(val)
        return base == 9 or base == 10 or base == 11  -- WATER, POISON_WATER, BLACK_WATER
    end

    --- 计算单个瓦片的合并光照（玩家 + 篝火），结果缓存
    local function CalcTileLighting(col, row, playerGridX, playerGridY, playerLightRadius)
        local key = row * 10000 + col
        local cached = frameLightCache[key]
        if cached then return cached[1], cached[2], cached[3] end

        -- 玩家光源
        local pLit, pLdx, pLdy = SolidRenderer.CalcPlayerLightDirection(
            col, row, playerGridX, playerGridY, playerLightRadius)

        -- 篝火光源（使用预解析列表，避免每瓦片 string:match）
        local bLit, bLdx, bLdy = 0, 0, 0
        for i = 1, #cachedCampfires do
            local cp = cachedCampfires[i]
            local lit2, ldx2, ldy2 = SolidRenderer.CalcPlayerLightDirection(
                col, row, cp[2], cp[1], 4)
            if lit2 > bLit then
                bLit, bLdx, bLdy = lit2, ldx2, ldy2
            end
        end

        -- 合并
        local totalLit = math.min(1.0, pLit + bLit)
        local totalLdx = pLdx * pLit + bLdx * bLit
        local totalLdy = pLdy * pLit + bLdy * bLit
        local len = math.sqrt(totalLdx * totalLdx + totalLdy * totalLdy)
        if len > 0.01 then
            totalLdx = totalLdx / len
            totalLdy = totalLdy / len
        end

        frameLightCache[key] = {totalLit, totalLdx, totalLdy}
        return totalLit, totalLdx, totalLdy
    end

    function M.DrawMap()
        local vg = M.vg
        local GRID = Config.GRID
        local LevelManager = M._LevelManager
        local Physics = M._Physics
        local PlayerController = M._PlayerController
        local PixelSystem = M._PixelSystem
        local TILE = LevelManager.TILE
        -- 传入动画时间驱动萤火虫闪烁
        SolidRenderer.SetTime(M.gameTime)
        local startCol = math.max(1, math.floor(M.cameraX / GRID) + 1)
        local visW = Config.DESIGN_W * (Config.PLAYER_CONFIG.cameraZoom or 1.0)
        local endCol = math.min(Config.MAP_COLS, startCol + math.ceil(visW / GRID) + 2)

        -- 预算玩家光照参数（一帧内不变）
        local player = PlayerController.player
        local flameRatio = PixelSystem.alivePixels / math.max(1, PixelSystem.totalPixels)
        local playerLightRadius = Config.PLAYER_CONFIG.defaultLightDiameter * 0.5 * flameRatio
        local playerGridX = player.gridX
        local playerGridY = player.gridY + 1

        -- 光照缓存失效检测：仅当玩家整格位移、篝火状态变化或火焰比显著变化时才清空
        local curPlayerCol = math.floor(playerGridX + 0.5)
        local curPlayerRow = math.floor(playerGridY + 0.5)
        local curFlameQuant = math.floor(flameRatio * 10 + 0.5)  -- 量化到 10 级

        -- 预解析已激活篝火坐标
        local campfireCount = 0
        for cpKey, activated in pairs(LevelManager.checkpointActivated) do
            if activated then campfireCount = campfireCount + 1 end
        end

        local needInvalidate = (curPlayerCol ~= lastPlayerGridCol)
            or (curPlayerRow ~= lastPlayerGridRow)
            or (campfireCount ~= lastCampfireCount)
            or (curFlameQuant ~= lastFlameRatioQuant)

        if needInvalidate then
            lastPlayerGridCol = curPlayerCol
            lastPlayerGridRow = curPlayerRow
            lastCampfireCount = campfireCount
            lastFlameRatioQuant = curFlameQuant
            frameLightCache = {}
            -- 预解析已激活篝火坐标（避免在每个瓦片内 string:match）
            cachedCampfires = {}
            for cpKey, activated in pairs(LevelManager.checkpointActivated) do
                if activated then
                    local cpRow, cpCol = cpKey:match("(%d+)_(%d+)")
                    cpRow, cpCol = tonumber(cpRow), tonumber(cpCol)
                    if cpRow and cpCol then
                        cachedCampfires[#cachedCampfires + 1] = {cpRow, cpCol}
                    end
                end
            end
        end

        for row = 1, Config.MAP_ROWS do
            for col = startCol, endCol do
                local val = LevelManager.levelData[row][col]
                if not val or val == TILE.EMPTY then goto continueTile end

                local base, group = Physics.GetTileType(val)
                local px = (col - 1) * GRID - M.cameraX
                local py = (row - 1) * GRID

                if base == TILE.SOLID or base == TILE.SOLID_PILLAR or base == TILE.SOLID_SEWER
                    or (base >= 19 and base <= 22) then  -- includes slopes
                    -- 使用持久缓存计算光照（避免重复 Bresenham）
                    local totalLit, totalLdx, totalLdy = CalcTileLighting(
                        col, row, playerGridX, playerGridY, playerLightRadius)

                    -- 性能优化：完全黑暗的瓦片跳过渲染（FogOfWar 会覆盖为黑色）
                    if totalLit < 0.01 then goto continueTile end

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
                    local revealTime = LevelManager.hiddenWallRevealed[group]
                    local shouldDraw = false
                    local alpha = 1.0
                    if not revealTime then
                        -- 未揭示，完全不透明渲染
                        shouldDraw = true
                        alpha = 1.0
                    else
                        -- 已揭示，计算渐变 alpha
                        local elapsed = M.gameTime - revealTime
                        local fadeDuration = LevelManager.HIDDEN_WALL_FADE_DURATION
                        if elapsed < fadeDuration then
                            shouldDraw = true
                            alpha = 1.0 - (elapsed / fadeDuration)
                        end
                    end
                    if shouldDraw then
                        -- 渲染为砖块样式（与 SOLID 相同外观），带 alpha 渐变
                        local pLit, pLdx, pLdy = CalcTileLighting(
                            col, row, playerGridX, playerGridY, playerLightRadius)
                        local neighbors = {
                            top    = IsSolidAt(row - 1, col),
                            bottom = IsSolidAt(row + 1, col),
                            left   = IsSolidAt(row, col - 1),
                            right  = IsSolidAt(row, col + 1),
                        }
                        if alpha < 1.0 then
                            nvgGlobalAlpha(vg, alpha)
                        end
                        SolidRenderer.DrawSolid(vg, TILE.SOLID, px, py, GRID, pLit, pLdx, pLdy, col, row, neighbors)
                        if alpha < 1.0 then
                            nvgGlobalAlpha(vg, 1.0)
                        end
                    end

                elseif base == TILE.CHECKPOINT then
                    M.DrawCheckpointTile(px, py, row, col)

                elseif base == TILE.CURTAIN then
                    -- 计算光照（使用帧级缓存）
                    local totalLit, totalLdx, totalLdy = CalcTileLighting(
                        col, row, playerGridX, playerGridY, playerLightRadius)

                    -- 检查上下相邻是否也是柳条
                    local hasAbove = false
                    local hasBelow = false
                    if row > 1 then
                        local aboveVal = LevelManager.levelData[row - 1][col]
                        if aboveVal and aboveVal ~= 0 then
                            local aboveBase = Physics.GetTileType(aboveVal)
                            hasAbove = (aboveBase == TILE.CURTAIN)
                        end
                    end
                    if row < Config.MAP_ROWS then
                        local belowVal = LevelManager.levelData[row + 1][col]
                        if belowVal and belowVal ~= 0 then
                            local belowBase = Physics.GetTileType(belowVal)
                            hasBelow = (belowBase == TILE.CURTAIN)
                        end
                    end

                    CurtainRenderer.DrawCurtain(vg, px, py, GRID, totalLit, totalLdx, totalLdy,
                        col, row, M.gameTime, hasAbove, hasBelow)

                elseif base == TILE.ABILITY_POINT then
                    local key = row .. "_" .. col
                    if not LevelManager.collectedItems[key] then
                        M.DrawAbilityPointTile(px, py, row, col)
                    end
                end

                ::continueTile::
            end
        end
    end
end

return Map
