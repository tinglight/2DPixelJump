------------------------------------------------------------
-- editor/GMTool.lua — 试玩模式 GM 工具（仅编辑器试玩有效）
-- 功能：无限能量、无限生命、最大跳跃(不消耗能量)、获得能力点
-- 渲染位置：外部 HUD 顶部栏（不遮挡游戏场景）
------------------------------------------------------------
local C = require("editor.Constants")
local S = require("editor.State")

local M = {}

-- ====================================================================
-- GM 状态
-- ====================================================================
M.enabled = false           -- GM 工具是否激活（仅编辑器试玩模式）
M.menuOpen = false          -- 菜单面板是否展开

-- GM 开关
M.infiniteEnergy = false    -- 无限能量（火焰不减少）
M.infiniteLife = false      -- 无限生命（不会死亡）
M.maxJumpNoCost = false     -- 跳跃最高且不消耗能量
M.grantAbility = false      -- 获得能力点（一次性）

-- ====================================================================
-- HUD 布局常量（屏幕设计坐标系）
-- ====================================================================
local GM_BTN_X = 180        -- GM 按钮 X 位置（JUMP 后面）
local GM_BTN_W = 28         -- GM 按钮宽度
local GM_BTN_H = 16         -- GM 按钮高度
local MENU_ITEM_H = 20      -- 下拉菜单每项高度
local MENU_W = 100          -- 下拉菜单宽度
local MENU_PAD = 3          -- 下拉菜单内边距

-- ====================================================================
-- 初始化
-- ====================================================================

--- 重置 GM 工具状态（每次进入试玩时调用）
function M.Reset()
    M.menuOpen = false
    M.infiniteEnergy = false
    M.infiniteLife = false
    M.maxJumpNoCost = false
    M.grantAbility = false
end

--- 初始化按钮位置（兼容旧接口，现在不需要做什么）
function M.InitPosition()
    -- 位置固定在 HUD 栏，无需动态初始化
end

-- ====================================================================
-- 判断是否处于编辑器试玩模式（非主菜单正式游戏）
-- ====================================================================
function M.IsActive()
    if S.fromMainMenu then return false end
    return S.editorMode == C.MODE_PLAY or S.editorMode == C.MODE_WORLDPLAY
end

--- 是否正在拖拽按钮（已移除拖拽，始终返回 false）
function M.IsDragging()
    return false
end

-- ====================================================================
-- 菜单数据
-- ====================================================================

local function GetMenuItems()
    return {
        { label = "无限能量", key = "infiniteEnergy", active = M.infiniteEnergy },
        { label = "无限生命", key = "infiniteLife", active = M.infiniteLife },
        { label = "最高跳跃", key = "maxJumpNoCost", active = M.maxJumpNoCost },
        { label = "获得能力", key = "grantAbility", active = S.play.hasFireball },
    }
end

-- ====================================================================
-- 获取按钮和菜单几何信息（供输入和渲染共享）
-- ====================================================================

--- 获取 GM 按钮在 HUD 栏中的矩形（屏幕设计坐标）
---@param barH number HUD 栏高度
---@return number x, number y, number w, number h
function M.GetButtonRect(barH)
    local y = (barH - GM_BTN_H) * 0.5
    return GM_BTN_X, y, GM_BTN_W, GM_BTN_H
end

--- 获取下拉菜单矩形（屏幕设计坐标，展开在 HUD 栏下方）
---@param barH number HUD 栏高度
---@return number x, number y, number w, number h
function M.GetMenuRect(barH)
    local items = GetMenuItems()
    local menuH = #items * MENU_ITEM_H + MENU_PAD * 2
    return GM_BTN_X, barH, MENU_W, menuH
end

-- ====================================================================
-- 输入处理（在屏幕设计坐标系下）
-- ====================================================================

--- 处理 HUD 栏点击，返回 true 表示事件被 GM 工具消费
---@param mx number 屏幕设计坐标 X
---@param my number 屏幕设计坐标 Y
---@param barH number HUD 栏高度
---@return boolean consumed
function M.HandleHUDClick(mx, my, barH)
    if not M.IsActive() then return false end

    -- 检查是否点击了下拉菜单项
    if M.menuOpen then
        local menuX, menuY, menuW, menuH = M.GetMenuRect(barH)
        if mx >= menuX and mx < menuX + menuW and my >= menuY and my < menuY + menuH then
            local idx = math.floor((my - menuY - MENU_PAD) / MENU_ITEM_H) + 1
            local items = GetMenuItems()
            if idx >= 1 and idx <= #items then
                local item = items[idx]
                if item.key == "infiniteEnergy" then
                    M.infiniteEnergy = not M.infiniteEnergy
                elseif item.key == "infiniteLife" then
                    M.infiniteLife = not M.infiniteLife
                elseif item.key == "maxJumpNoCost" then
                    M.maxJumpNoCost = not M.maxJumpNoCost
                elseif item.key == "grantAbility" then
                    S.play.hasFireball = true
                    S.SetMessage("GM: 已获得火球能力!", 1.5)
                end
            end
            return true
        end
        -- 点击菜单外区域，关闭菜单
        M.menuOpen = false
        return true
    end

    -- 检查是否点击了 GM 按钮
    local bx, by, bw, bh = M.GetButtonRect(barH)
    if mx >= bx and mx < bx + bw and my >= by and my < by + bh then
        M.menuOpen = not M.menuOpen
        return true
    end

    return false
end

--- 旧接口兼容（play view 坐标系 → 不再使用，直接返回 false）
function M.HandleMouseDown(pmx, pmy)
    return false
end

function M.HandleMouseMove(pmx, pmy)
    return false
end

function M.HandleMouseUp(pmx, pmy)
    return false
end

-- ====================================================================
-- GM 效果应用（每帧调用）
-- ====================================================================

--- 每帧更新 GM 效果
function M.ApplyEffects()
    if not M.IsActive() then return end

    -- 无限能量：保持火焰满值
    if M.infiniteEnergy then
        S.playAlivePixels = S.playTotalPixels
    end

    -- 无限生命：强制存活
    if M.infiniteLife then
        S.play.alive = true
    end

    -- 最高跳跃且不消耗能量：设置 fallGridCount 为最大
    if M.maxJumpNoCost then
        local maxJump = S.playerParams.maxJumpGrids
        if maxJump <= 0 then maxJump = 50 end
        local baseJump = S.playerParams.baseJumpGrids or 3
        local mult = S.playerParams.fallJumpMultiplier or 1.0
        if mult > 0 then
            S.play.fallGridCount = math.ceil((maxJump - baseJump) / mult)
        else
            S.play.fallGridCount = maxJump
        end
        -- 同时保持能量不减
        S.playAlivePixels = S.playTotalPixels
    end
end

-- ====================================================================
-- 渲染（在 HUD 栏的屏幕设计坐标系下）
-- ====================================================================

--- 在 HUD 栏绘制 GM 按钮和展开的下拉列表
---@param vg userdata NanoVG 上下文
---@param barH number HUD 栏高度
function M.DrawHUD(vg, barH)
    local bx, by, bw, bh = M.GetButtonRect(barH)
    local anyActive = M.infiniteEnergy or M.infiniteLife or M.maxJumpNoCost

    -- GM 按钮背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, bw, bh, 3)
    if anyActive then
        nvgFillColor(vg, nvgRGBA(180, 40, 40, 230))
    elseif M.menuOpen then
        nvgFillColor(vg, nvgRGBA(80, 70, 50, 230))
    else
        nvgFillColor(vg, nvgRGBA(50, 45, 60, 220))
    end
    nvgFill(vg)

    -- 按钮边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, bw, bh, 3)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 80, anyActive and 255 or 140))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 按钮文字 "GM"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgText(vg, bx + bw * 0.5, by + bh * 0.5, "GM")

    -- 展开的下拉菜单
    if M.menuOpen then
        M.DrawDropdown(vg, barH)
    end
end

--- 绘制 GM 下拉菜单（在 HUD 栏下方展开）
---@param vg userdata NanoVG 上下文
---@param barH number HUD 栏高度
function M.DrawDropdown(vg, barH)
    local items = GetMenuItems()
    local menuX, menuY, menuW, menuH = M.GetMenuRect(barH)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, menuX, menuY, menuW, menuH, 4)
    nvgFillColor(vg, nvgRGBA(20, 18, 30, 240))
    nvgFill(vg)

    -- 面板边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, menuX, menuY, menuW, menuH, 4)
    nvgStrokeColor(vg, nvgRGBA(255, 180, 80, 160))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 菜单项
    nvgFontFace(vg, "sans")
    for i, item in ipairs(items) do
        local iy = menuY + MENU_PAD + (i - 1) * MENU_ITEM_H
        local isActive = item.active

        -- 激活背景
        if isActive then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, menuX + 2, iy + 1, menuW - 4, MENU_ITEM_H - 2, 3)
            nvgFillColor(vg, nvgRGBA(60, 140, 60, 100))
            nvgFill(vg)
        end

        -- 开关指示圆点
        local dotX = menuX + 10
        local dotY = iy + MENU_ITEM_H * 0.5
        nvgBeginPath(vg)
        nvgCircle(vg, dotX, dotY, 3)
        if isActive then
            nvgFillColor(vg, nvgRGBA(80, 255, 80, 255))
        else
            nvgFillColor(vg, nvgRGBA(100, 100, 100, 200))
        end
        nvgFill(vg)

        -- 标签文字
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(200, 255, 200, 255))
        else
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
        end
        nvgText(vg, menuX + 20, dotY, item.label)
    end
end

--- 旧渲染接口（不再使用）
function M.Draw(vg)
    -- 已迁移到 DrawHUD
end

function M.DrawButton(vg) end
function M.DrawMenu(vg) end

return M
