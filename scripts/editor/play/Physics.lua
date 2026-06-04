------------------------------------------------------------
-- editor/play/Physics.lua — 碰撞与地形判定
------------------------------------------------------------
local C = require("editor.Constants")
local S = require("editor.State")
local TileUtils = require("editor.TileUtils")

local Physics = {}

---@param M table PlayMode module
function Physics.Attach(M)

    function M.PlayerGridSize()
        local totalPx = C.FLAME_CFG.pixelGridSize * C.FLAME_CFG.pixelSize
        return math.ceil(totalPx / C.GRID)
    end

    function M.IsSolid(col, row)
        if col < 1 or col > S.MAP_COLS then return true end
        if row < 1 then return false end
        if row > S.MAP_ROWS then return true end
        local val = S.levelData[row][col]
        local base, group = TileUtils.GetTileType(val)
        if base == C.TILE.SOLID or base == C.TILE.SOLID_PILLAR or base == C.TILE.SOLID_SEWER
            or base == C.TILE.SLOPE_TR or base == C.TILE.SLOPE_TL or base == C.TILE.SLOPE_BR or base == C.TILE.SLOPE_BL then return true end
        if base == C.TILE.GATE and not S.play.switchState[group] then return true end
        if base == C.TILE.HIDDEN_WALL then
            local revealTime = S.play.hiddenWallRevealed[group]
            if not revealTime then return true end
            -- 渐变中仍保持碰撞
            if S.play.gameTime - revealTime < C.HIDDEN_WALL_FADE_DURATION then return true end
        end
        if base == C.TILE.FRAGILE and not S.play.fragileGone[row .. "_" .. col] then return true end
        return false
    end

    --- 检查某格是否为实体方块（用于渲染时邻居检测，包含未完全消失的隐藏墙）
    function M.IsSolidAt(row, col)
        if row < 1 or row > S.MAP_ROWS or col < 1 or col > S.MAP_COLS then
            return false
        end
        local val = S.levelData[row][col]
        if not val or val == 0 then return false end
        local base, group = TileUtils.GetTileType(val)
        if base == C.TILE.SOLID or base == C.TILE.SOLID_PILLAR or base == C.TILE.SOLID_SEWER
            or base == C.TILE.SLOPE_TR or base == C.TILE.SLOPE_TL or base == C.TILE.SLOPE_BR or base == C.TILE.SLOPE_BL then
            return true
        end
        -- 隐藏墙：未揭示或正在渐变中也算实体（用于法线计算）
        if base == C.TILE.HIDDEN_WALL then
            local revealTime = S.play.hiddenWallRevealed[group]
            if not revealTime then return true end
            if S.play.gameTime - revealTime < C.HIDDEN_WALL_FADE_DURATION then return true end
        end
        return false
    end

    --- 检测指定位置是否为柱子（用于柱子衔接渲染）
    function M.IsPillarAt(row, col)
        if row < 1 or row > S.MAP_ROWS or col < 1 or col > S.MAP_COLS then
            return false
        end
        local val = S.levelData[row][col]
        if not val or val == 0 then return false end
        local base = TileUtils.GetTileType(val)
        return base == C.TILE.SOLID_PILLAR
    end

    --- 检测玩家是否在梯子上（任意身体格子重叠梯子）
    function M.IsOnLadder(gx, gy)
        local s = M.PlayerGridSize()
        for dy = 0, s - 1 do
            for dx = 0, s - 1 do
                local col = gx + dx
                local row = gy + dy
                if col >= 1 and col <= S.MAP_COLS and row >= 1 and row <= S.MAP_ROWS then
                    local val = S.levelData[row][col]
                    local base = TileUtils.GetTileType(val)
                    if base == C.TILE.LADDER then return true end
                end
            end
        end
        return false
    end

    function M.OnGround(gx, gy)
        local s = M.PlayerGridSize()
        local feetRow = gy + s
        for dx = 0, s - 1 do
            if M.IsSolid(gx + dx, feetRow) then return true end
        end
        return false
    end

    function M.Collides(gx, gy)
        local s = M.PlayerGridSize()
        for dy = 0, s - 1 do
            for dx = 0, s - 1 do
                if M.IsSolid(gx + dx, gy + dy) then return true end
            end
        end
        return false
    end

    --- 判断某格是否为实体（不含斜坡，用于玩家水平移动碰撞）
    function M.IsSolidNonSlope(col, row)
        if col < 1 or col > S.MAP_COLS then return true end
        if row < 1 then return false end
        if row > S.MAP_ROWS then return true end
        local val = S.levelData[row][col]
        local base, group = TileUtils.GetTileType(val)
        if base == C.TILE.SOLID or base == C.TILE.SOLID_PILLAR or base == C.TILE.SOLID_SEWER then return true end
        if base == C.TILE.GATE and not S.play.switchState[group] then return true end
        if base == C.TILE.HIDDEN_WALL then
            local revealTime = S.play.hiddenWallRevealed[group]
            if not revealTime then return true end
            if S.play.gameTime - revealTime < C.HIDDEN_WALL_FADE_DURATION then return true end
        end
        if base == C.TILE.FRAGILE and not S.play.fragileGone[row .. "_" .. col] then return true end
        return false
    end

    --- 碰撞检测（忽略斜坡）
    function M.CollidesIgnoreSlopes(gx, gy)
        local s = M.PlayerGridSize()
        for dy = 0, s - 1 do
            for dx = 0, s - 1 do
                if M.IsSolidNonSlope(gx + dx, gy + dy) then return true end
            end
        end
        return false
    end

    --- 获取指定格子的斜坡类型（如果是斜坡返回 base，否则 nil）
    function M.GetSlopeAt(col, row)
        if col < 1 or col > S.MAP_COLS or row < 1 or row > S.MAP_ROWS then return nil end
        local val = S.levelData[row][col]
        local base = TileUtils.GetTileType(val)
        if base == C.TILE.SLOPE_TR or base == C.TILE.SLOPE_TL
            or base == C.TILE.SLOPE_BR or base == C.TILE.SLOPE_BL then
            return base
        end
        return nil
    end

    --- 判断斜坡与移动方向的关系（模块内 local，通过闭包被 MoveOneGrid 使用）
    ---@return boolean isUpSlope, boolean isDownSlope
    function M.PlaySlopeMovementType(slopeType, dir)
        if slopeType == C.TILE.SLOPE_TR then
            if dir == 1 then return true, false end   -- 右=上坡
            if dir == -1 then return false, true end  -- 左=下坡
        elseif slopeType == C.TILE.SLOPE_TL then
            if dir == -1 then return true, false end
            if dir == 1 then return false, true end
        elseif slopeType == C.TILE.SLOPE_BR then
            if dir == 1 then return false, true end
            if dir == -1 then return true, false end
        elseif slopeType == C.TILE.SLOPE_BL then
            if dir == -1 then return false, true end
            if dir == 1 then return true, false end
        end
        return false, false
    end

end

return Physics
