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

                elseif base == TILE.WATER then
                    M.DrawWaterTile(vg, px, py, row, col, TILE.WATER)

                elseif base == TILE.POISON_WATER then
                    M.DrawWaterTile(vg, px, py, row, col, TILE.POISON_WATER)

                elseif base == TILE.BLACK_WATER then
                    M.DrawWaterTile(vg, px, py, row, col, TILE.BLACK_WATER)

                elseif base == TILE.LADDER then
                    M.DrawLadderTile(vg, px, py, row, col)

                elseif base == TILE.PIPE then
                    -- 管道：简单灰色方块
                    nvgBeginPath(vg)
                    nvgRect(vg, px + 1, py + 1, GRID - 2, GRID - 2)
                    nvgFillColor(vg, nvgRGBA(80, 90, 80, 200))
                    nvgFill(vg)

                elseif base == TILE.FRAGILE then
                    -- 脆弱方块：带裂缝的方块
                    nvgBeginPath(vg)
                    nvgRect(vg, px, py, GRID, GRID)
                    nvgFillColor(vg, nvgRGBA(120, 100, 70, 200))
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, px + 3, py + GRID * 0.3)
                    nvgLineTo(vg, px + GRID * 0.5, py + GRID * 0.5)
                    nvgLineTo(vg, px + GRID - 4, py + GRID * 0.7)
                    nvgStrokeColor(vg, nvgRGBA(60, 50, 30, 180))
                    nvgStrokeWidth(vg, 1)
                    nvgStroke(vg)

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
    -- ================================================================
    -- 水体绘制（WATER / POISON_WATER / BLACK_WATER）
    -- ================================================================
    function M.DrawWaterTile(vg, px, py, row, col, waterType)
        local GRID = Config.GRID
        local LevelManager = M._LevelManager
        local Physics = M._Physics
        local TILE = LevelManager.TILE
        local t = M.gameTime
        local worldX = (col - 1) * GRID

        -- 检测上方是否同类水体（决定是否画水面波浪）
        local hasWaterAbove = false
        if row > 1 and LevelManager.levelData[row - 1] then
            local aboveVal = LevelManager.levelData[row - 1][col]
            if aboveVal then
                local aboveBase = Physics.GetTileType(aboveVal)
                if aboveBase == waterType then hasWaterAbove = true end
            end
        end

        -- 根据水体类型选颜色
        local baseR, baseG, baseB, deepR, deepG, deepB, sparkR, sparkG, sparkB
        if waterType == TILE.POISON_WATER then
            baseR, baseG, baseB = 20, 140, 40
            deepR, deepG, deepB = 10, 100, 25
            sparkR, sparkG, sparkB = 120, 255, 130
        elseif waterType == TILE.BLACK_WATER then
            baseR, baseG, baseB = 40, 40, 50
            deepR, deepG, deepB = 30, 30, 38
            sparkR, sparkG, sparkB = 140, 140, 160
        else -- WATER
            baseR, baseG, baseB = 40, 100, 240
            deepR, deepG, deepB = 20, 60, 160
            sparkR, sparkG, sparkB = 150, 220, 255
        end

        if not hasWaterAbove then
            -- 水面：波浪动画
            local freq = waterType == TILE.BLACK_WATER and 0.28 or (waterType == TILE.POISON_WATER and 0.4 or 0.35)
            local layers = waterType == TILE.BLACK_WATER and 2 or 3
            for layer = 1, layers do
                local speed = 2.5 + layer * 0.8
                if waterType == TILE.BLACK_WATER then speed = 1.2 + layer * 0.4 end
                local amp = 1.5 - layer * 0.3
                local yBase = py + 2 + layer * 3.5
                if waterType == TILE.BLACK_WATER then yBase = py + 3 + layer * 4.5 end
                local phase = t * speed + layer * 2.1
                nvgBeginPath(vg)
                nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
                for sx = 1, 4 do
                    local localX = sx * (GRID / 4)
                    nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
                end
                nvgLineTo(vg, px + GRID, py + GRID)
                nvgLineTo(vg, px, py + GRID)
                nvgClosePath(vg)
                local a = math.floor(40 + layer * 15)
                nvgFillColor(vg, nvgRGBA(baseR + layer * 20, baseG + layer * 25, baseB, a))
                nvgFill(vg)
            end
        else
            -- 深层水体：实心背景 + 微弱波纹
            nvgBeginPath(vg)
            nvgRect(vg, px, py, GRID, GRID)
            nvgFillColor(vg, nvgRGBA(deepR, deepG, deepB, waterType == TILE.BLACK_WATER and 220 or 180))
            nvgFill(vg)
            local freq = 0.25
            for layer = 1, 2 do
                local speed = 1.0 + layer * 0.3
                local amp = 0.8
                local yBase = py + GRID * (0.3 + layer * 0.25)
                local phase = t * speed + row * 1.7 + layer * 3.0
                nvgBeginPath(vg)
                nvgMoveTo(vg, px, yBase + math.sin(phase + worldX * freq) * amp)
                for sx = 1, 4 do
                    local localX = sx * (GRID / 4)
                    nvgLineTo(vg, px + localX, yBase + math.sin(phase + (worldX + localX) * freq) * amp)
                end
                nvgLineTo(vg, px + GRID, yBase + math.sin(phase + (worldX + GRID) * freq) * amp - 1)
                nvgLineTo(vg, px + GRID, yBase + 2)
                nvgLineTo(vg, px, yBase + 2)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(deepR + layer * 15, deepG + layer * 20, deepB + 20, 30 + layer * 12))
                nvgFill(vg)
            end
        end

        -- 水面闪烁
        local sparkTopY = hasWaterAbove and 2 or math.floor(GRID * 0.55)
        local sparkRangeH = GRID - sparkTopY - 2
        local seed = col * 7 + row * 13
        for i = 1, 3 do
            local phase_i = t * (3.0 + i * 0.7) + seed + i * 5.3
            local sparkAlpha = math.sin(phase_i) * 0.5 + 0.5
            if sparkAlpha > 0.3 then
                local sx = px + 2 + math.fmod(seed * i * 3.7, GRID - 4)
                local sy = py + sparkTopY + math.fmod(seed * i * 2.3, math.max(1, sparkRangeH))
                nvgBeginPath(vg)
                nvgRect(vg, sx, sy, 1, 1)
                nvgFillColor(vg, nvgRGBA(sparkR, sparkG, sparkB, math.floor(200 * sparkAlpha)))
                nvgFill(vg)
            end
        end
    end

    -- ================================================================
    -- 梯子绘制（2 格宽像素风格，左格绘制，右格跳过）
    -- ================================================================
    function M.DrawLadderTile(vg, px, py, row, col)
        local LevelManager = M._LevelManager
        local Physics = M._Physics
        local TILE = LevelManager.TILE
        local GRID = Config.GRID

        -- 如果左邻是 LADDER，当前是右半部分，跳过绘制
        if col > 1 then
            local leftVal = LevelManager.levelData[row][col - 1]
            if leftVal then
                local leftBase = Physics.GetTileType(leftVal)
                if leftBase == TILE.LADDER then return end
            end
        end

        local P = 2  -- 像素块大小
        local lx = px
        local ly = py

        local darkWood   = nvgRGBA(58, 40, 22, 255)
        local midWood    = nvgRGBA(82, 55, 30, 255)
        local hiWood     = nvgRGBA(105, 72, 38, 255)
        local rungMain   = nvgRGBA(95, 65, 35, 255)
        local rungHi     = nvgRGBA(120, 85, 48, 255)
        local shadowWood = nvgRGBA(35, 24, 12, 255)
        local moss1      = nvgRGBA(40, 85, 30, 255)
        local moss2      = nvgRGBA(58, 110, 42, 220)
        local vine       = nvgRGBA(32, 70, 28, 240)
        local decay      = nvgRGBA(50, 45, 25, 200)

        local function pix(cx, cy, color)
            nvgBeginPath(vg)
            nvgRect(vg, lx + cx * P, ly + cy * P, P, P)
            nvgFillColor(vg, color)
            nvgFill(vg)
        end

        -- 左侧柱子
        for r = 0, 7 do
            pix(1, r, midWood)
            pix(2, r, darkWood)
        end
        pix(1, 0, hiWood) pix(1, 2, hiWood) pix(1, 5, hiWood)
        pix(2, 3, shadowWood) pix(1, 6, shadowWood)

        -- 右侧柱子
        for r = 0, 7 do
            pix(13, r, darkWood)
            pix(14, r, midWood)
        end
        pix(14, 1, hiWood) pix(14, 4, hiWood) pix(14, 6, hiWood)
        pix(13, 2, shadowWood) pix(14, 5, shadowWood)

        -- 上横档
        for c = 3, 12 do pix(c, 2, rungMain) end
        pix(4, 2, rungHi) pix(6, 2, rungHi) pix(9, 2, rungHi) pix(11, 2, rungHi)
        for c = 3, 12 do pix(c, 3, shadowWood) end

        -- 下横档
        for c = 3, 12 do pix(c, 5, rungMain) end
        pix(3, 5, rungHi) pix(5, 5, rungHi) pix(8, 5, rungHi) pix(10, 5, rungHi)
        for c = 3, 12 do pix(c, 6, shadowWood) end

        -- 苔藓/藤蔓/腐朽点缀
        pix(0, 0, moss1) pix(1, 0, moss2) pix(0, 1, moss2)
        pix(15, 6, vine) pix(15, 7, vine) pix(14, 7, moss2)
        pix(5, 2, moss1) pix(7, 5, moss1)
        pix(9, 5, decay) pix(2, 4, decay) pix(13, 6, decay)
        pix(0, 4, vine) pix(0, 5, moss2)
    end
end

return Map
