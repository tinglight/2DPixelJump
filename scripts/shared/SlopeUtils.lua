------------------------------------------------------------
-- shared/SlopeUtils.lua — 斜坡方向判定（纯函数，无外部依赖）
-- 供 gameplay/Physics 和 editor/play/Physics 共用
------------------------------------------------------------

local M = {}

-- 斜坡枚举值（与 editor/Constants.lua 和 level/LevelGenerator.lua 一致）
local SLOPE_TR = 19
local SLOPE_TL = 20
local SLOPE_BR = 21
local SLOPE_BL = 22

--- 判断斜坡与移动方向的关系
---@param slopeType integer 斜坡 tile 枚举值 (19-22)
---@param dir integer 移动方向 (1=右, -1=左)
---@return boolean isUpSlope, boolean isDownSlope
function M.SlopeMovementType(slopeType, dir)
    if slopeType == SLOPE_TR then
        if dir == 1 then return true, false end
        if dir == -1 then return false, true end
    elseif slopeType == SLOPE_TL then
        if dir == -1 then return true, false end
        if dir == 1 then return false, true end
    elseif slopeType == SLOPE_BR then
        if dir == 1 then return false, true end
        if dir == -1 then return true, false end
    elseif slopeType == SLOPE_BL then
        if dir == -1 then return false, true end
        if dir == 1 then return true, false end
    end
    return false, false
end

return M
