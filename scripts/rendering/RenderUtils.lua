-- ====================================================================
-- RenderUtils.lua - 渲染通用辅助函数
-- ====================================================================
-- 从 SolidRenderer / FogOfWar 等模块提取的高频重复模式
-- ====================================================================

local M = {}

--- 颜色值钳制到 [0, 255] 并取整
---@param val number
---@return integer
function M.clamp255(val)
    if val <= 0 then return 0 end
    if val >= 255 then return 255 end
    return math.floor(val)
end

--- 填充单色矩形（替换 nvgBeginPath/nvgRect/nvgFillColor/nvgFill 四行模式）
---@param vg userdata
---@param x number
---@param y number
---@param w number
---@param h number
---@param r integer
---@param g integer
---@param b integer
---@param a integer
function M.fillRect(vg, x, y, w, h, r, g, b, a)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, nvgRGBA(r, g, b, a))
    nvgFill(vg)
end

return M
