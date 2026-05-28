-- ====================================================================
-- editor/Sidebar.lua - 侧边栏（已保存关卡列表）渲染与命中检测
-- ====================================================================

local C = require "editor.Constants"
local S = require "editor.State"

local M = {}

-- ====================================================================
-- 布局常量
-- ====================================================================
local ITEM_H = 22
local ACTION_BTN_SIZE = 14
local ACTION_PAD = 2

-- ====================================================================
-- 内部：获取侧边栏矩形范围
-- ====================================================================
local function GetSidebarRect()
    local sbX = S.screenDesignW - C.SIDEBAR_W
    local sbY = C.TOPBAR_H
    local sbH = S.screenDesignH - C.TOPBAR_H - C.BOTTOMBAR_H
    return sbX, sbY, sbH
end

-- ====================================================================
-- 内部：获取设计坐标鼠标位置
-- ====================================================================
local function GetDesignMouse()
    local mx = input:GetMousePosition().x / S.dpr / S.scaleF
    local my = input:GetMousePosition().y / S.dpr / S.scaleF
    return mx, my
end

-- ====================================================================
-- Draw - 绘制侧边栏
-- ====================================================================
function M.Draw()
    if not S.sidebarOpen then return end
    local vg = S.vg
    local sbX, sbY, sbH = GetSidebarRect()

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, sbX, sbY, C.SIDEBAR_W, sbH)
    nvgFillColor(vg, nvgRGBA(22, 22, 35, 245))
    nvgFill(vg)

    -- 左边框
    nvgBeginPath(vg)
    nvgMoveTo(vg, sbX, sbY)
    nvgLineTo(vg, sbX, sbY + sbH)
    nvgStrokeColor(vg, nvgRGBA(80, 80, 100, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 200, 80, 255))
    nvgText(vg, sbX + C.SIDEBAR_W * 0.5, sbY + 10, "已保存关卡")

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, sbX + 6, sbY + 20)
    nvgLineTo(vg, sbX + C.SIDEBAR_W - 6, sbY + 20)
    nvgStrokeColor(vg, nvgRGBA(60, 60, 80, 255))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    -- 关卡列表（带裁剪）
    nvgSave(vg)
    nvgScissor(vg, sbX, sbY + 22, C.SIDEBAR_W, sbH - 22)

    if #S.savedLevels == 0 then
        M.DrawEmptyHint(vg, sbX, sbY, sbH)
    else
        M.DrawLevelItems(vg, sbX, sbY, sbH)
    end

    nvgRestore(vg)
end

-- ====================================================================
-- DrawEmptyHint - 空列表提示
-- ====================================================================
function M.DrawEmptyHint(vg, sbX, sbY, sbH)
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(120, 120, 140, 200))
    nvgText(vg, sbX + C.SIDEBAR_W * 0.5, sbY + sbH * 0.5, "暂无保存")
end

-- ====================================================================
-- DrawLevelItems - 逐条绘制关卡列表
-- ====================================================================
function M.DrawLevelItems(vg, sbX, sbY, sbH)
    local listY = sbY + 24 - S.sidebarScroll
    local mx, my = GetDesignMouse()

    for i, lv in ipairs(S.savedLevels) do
        local iy = listY + (i - 1) * ITEM_H
        if iy + ITEM_H >= sbY + 22 and iy <= sbY + sbH then
            M.DrawSingleItem(vg, lv, i, sbX, iy, mx, my)
        end
    end
end

-- ====================================================================
-- DrawSingleItem - 绘制单个关卡条目
-- ====================================================================
function M.DrawSingleItem(vg, lv, index, sbX, iy, mx, my)
    local isCurrent = (lv.file == S.currentLevelName)
    local isSelected = (lv.file == S.sidebarLastClickFile) and not isCurrent
    local isHover = mx >= sbX and mx < sbX + C.SIDEBAR_W and my >= iy and my < iy + ITEM_H

    -- 背景
    if isCurrent then
        nvgBeginPath(vg)
        nvgRect(vg, sbX + 4, iy + 1, C.SIDEBAR_W - 8, ITEM_H - 2)
        nvgFillColor(vg, nvgRGBA(60, 80, 40, 200))
        nvgFill(vg)
    elseif isSelected then
        nvgBeginPath(vg)
        nvgRect(vg, sbX + 4, iy + 1, C.SIDEBAR_W - 8, ITEM_H - 2)
        nvgFillColor(vg, nvgRGBA(50, 60, 90, 200))
        nvgFill(vg)
    elseif isHover then
        nvgBeginPath(vg)
        nvgRect(vg, sbX + 4, iy + 1, C.SIDEBAR_W - 8, ITEM_H - 2)
        nvgFillColor(vg, nvgRGBA(50, 50, 70, 200))
        nvgFill(vg)
    end

    -- 关卡名
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, isCurrent and nvgRGBA(150, 255, 150, 255) or nvgRGBA(200, 200, 210, 255))
    nvgText(vg, sbX + 10, iy + ITEM_H * 0.5, lv.name)

    -- 悬停时显示操作按钮
    if isHover then
        M.DrawItemActions(vg, sbX, iy, mx, my)
    end
end

-- ====================================================================
-- DrawItemActions - 绘制条目操作按钮（删除+重命名）
-- ====================================================================
function M.DrawItemActions(vg, sbX, iy, mx, my)
    local btnY2 = iy + (ITEM_H - ACTION_BTN_SIZE) * 0.5

    -- 删除按钮（最右）
    local delX = sbX + C.SIDEBAR_W - 8 - ACTION_BTN_SIZE
    local isDelHover = mx >= delX and mx < delX + ACTION_BTN_SIZE
        and my >= btnY2 and my < btnY2 + ACTION_BTN_SIZE

    nvgBeginPath(vg)
    nvgRoundedRect(vg, delX, btnY2, ACTION_BTN_SIZE, ACTION_BTN_SIZE, 2)
    nvgFillColor(vg, isDelHover and nvgRGBA(180, 50, 50, 220) or nvgRGBA(100, 40, 40, 180))
    nvgFill(vg)

    -- X 图标
    nvgBeginPath(vg)
    nvgMoveTo(vg, delX + 4, btnY2 + 4)
    nvgLineTo(vg, delX + ACTION_BTN_SIZE - 4, btnY2 + ACTION_BTN_SIZE - 4)
    nvgMoveTo(vg, delX + ACTION_BTN_SIZE - 4, btnY2 + 4)
    nvgLineTo(vg, delX + 4, btnY2 + ACTION_BTN_SIZE - 4)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 200, 255))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 重命名按钮
    local renX = delX - ACTION_BTN_SIZE - ACTION_PAD
    local isRenHover = mx >= renX and mx < renX + ACTION_BTN_SIZE
        and my >= btnY2 and my < btnY2 + ACTION_BTN_SIZE

    nvgBeginPath(vg)
    nvgRoundedRect(vg, renX, btnY2, ACTION_BTN_SIZE, ACTION_BTN_SIZE, 2)
    nvgFillColor(vg, isRenHover and nvgRGBA(60, 100, 160, 220) or nvgRGBA(40, 70, 120, 180))
    nvgFill(vg)

    -- 铅笔图标
    nvgBeginPath(vg)
    nvgMoveTo(vg, renX + 4, btnY2 + ACTION_BTN_SIZE - 5)
    nvgLineTo(vg, renX + ACTION_BTN_SIZE - 4, btnY2 + 4)
    nvgStrokeColor(vg, nvgRGBA(180, 210, 255, 255))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, renX + 3, btnY2 + ACTION_BTN_SIZE - 4)
    nvgLineTo(vg, renX + 7, btnY2 + ACTION_BTN_SIZE - 4)
    nvgStrokeColor(vg, nvgRGBA(180, 210, 255, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

-- ====================================================================
-- 命中检测
-- ====================================================================

---@param mx number 设计坐标鼠标x
---@param my number 设计坐标鼠标y
---@return boolean 点击是否在侧边栏区域内
function M.IsInSidebar(mx, my)
    if not S.sidebarOpen then return false end
    local sbX, sbY, sbH = GetSidebarRect()
    return mx >= sbX and mx < sbX + C.SIDEBAR_W and my >= sbY and my < sbY + sbH
end

---@class SidebarHitResult
---@field index number 关卡索引
---@field action string|nil "load"|"rename"|"delete"

---@param mx number
---@param my number
---@return SidebarHitResult|nil
function M.HitTest(mx, my)
    if not S.sidebarOpen then return nil end
    local sbX, sbY, sbH = GetSidebarRect()

    if mx < sbX or mx >= sbX + C.SIDEBAR_W then return nil end
    if my < sbY + 22 or my >= sbY + sbH then return nil end

    local listY = sbY + 24 - S.sidebarScroll

    for i, lv in ipairs(S.savedLevels) do
        local iy = listY + (i - 1) * ITEM_H
        if my >= iy and my < iy + ITEM_H then
            -- 检测操作按钮
            local btnY2 = iy + (ITEM_H - ACTION_BTN_SIZE) * 0.5
            local delX = sbX + C.SIDEBAR_W - 8 - ACTION_BTN_SIZE

            if mx >= delX and mx < delX + ACTION_BTN_SIZE
                and my >= btnY2 and my < btnY2 + ACTION_BTN_SIZE then
                return { index = i, action = "delete" }
            end

            local renX = delX - ACTION_BTN_SIZE - ACTION_PAD
            if mx >= renX and mx < renX + ACTION_BTN_SIZE
                and my >= btnY2 and my < btnY2 + ACTION_BTN_SIZE then
                return { index = i, action = "rename" }
            end

            return { index = i, action = "load" }
        end
    end
    return nil
end

---@param delta number 滚动增量
function M.Scroll(delta)
    S.sidebarScroll = math.max(0, S.sidebarScroll - delta * 20)
end

return M
