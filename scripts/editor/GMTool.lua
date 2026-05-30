------------------------------------------------------------
-- editor/GMTool.lua — 试玩模式 GM 工具（仅编辑器试玩有效）
-- 功能：无限能量、无限生命、最大跳跃(不消耗能量)、获得能力点
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
-- 按钮拖拽状态
-- ====================================================================
local BTN_SIZE = 24
local BTN_MARGIN = 4

-- 按钮位置（右侧中间，play view 坐标）
local btnX = 0
local btnY = 0
local dragging = false
local dragOffsetX = 0
local dragOffsetY = 0
local dragStartX = 0
local dragStartY = 0
local dragMoved = false     -- 拖拽过程中是否实际移动了（用于区分点击和拖拽）

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
    dragging = false
    dragMoved = false
end

--- 初始化按钮位置（需要在知道 playView 尺寸后调用）
function M.InitPosition()
    -- 按钮位置存储在输入坐标空间（不含 zoom: 0..playViewW）
    btnX = S.playViewW - BTN_SIZE - BTN_MARGIN
    btnY = S.playViewH * 0.4
end

-- ====================================================================
-- 判断是否处于编辑器试玩模式（非主菜单正式游戏）
-- ====================================================================
function M.IsActive()
    if S.fromMainMenu then return false end
    return S.editorMode == C.MODE_PLAY or S.editorMode == C.MODE_WORLDPLAY
end

--- 是否正在拖拽按钮
function M.IsDragging()
    return dragging
end

-- ====================================================================
-- 输入处理（在 play view 坐标系下）
-- ====================================================================

--- 处理鼠标/触摸按下，返回 true 表示事件被 GM 工具消费
---@param pmx number play view 坐标 X
---@param pmy number play view 坐标 Y
---@return boolean consumed
function M.HandleMouseDown(pmx, pmy)
    if not M.IsActive() then return false end

    -- 检查是否点击了菜单项
    if M.menuOpen then
        local consumed = M.HandleMenuClick(pmx, pmy)
        if consumed then return true end
    end

    -- 检查是否点击了 GM 按钮
    if pmx >= btnX and pmx < btnX + BTN_SIZE and pmy >= btnY and pmy < btnY + BTN_SIZE then
        dragging = true
        dragOffsetX = pmx - btnX
        dragOffsetY = pmy - btnY
        dragStartX = pmx
        dragStartY = pmy
        dragMoved = false
        return true
    end

    -- 点击了菜单外区域，关闭菜单
    if M.menuOpen then
        M.menuOpen = false
        return true
    end

    return false
end

--- 处理鼠标/触摸移动
---@param pmx number play view 坐标 X
---@param pmy number play view 坐标 Y
---@return boolean consumed
function M.HandleMouseMove(pmx, pmy)
    if not M.IsActive() then return false end
    if not dragging then return false end

    local dx = math.abs(pmx - dragStartX)
    local dy = math.abs(pmy - dragStartY)
    if dx > 3 or dy > 3 then
        dragMoved = true
    end

    if dragMoved then
        btnX = math.max(0, math.min(pmx - dragOffsetX, S.playViewW - BTN_SIZE))
        btnY = math.max(0, math.min(pmy - dragOffsetY, S.playViewH - BTN_SIZE))
    end
    return true
end

--- 处理鼠标/触摸释放
---@param pmx number play view 坐标 X
---@param pmy number play view 坐标 Y
---@return boolean consumed
function M.HandleMouseUp(pmx, pmy)
    if not M.IsActive() then return false end
    if not dragging then return false end

    dragging = false
    if not dragMoved then
        -- 没有移动 → 视为点击，切换菜单
        M.menuOpen = not M.menuOpen
    end
    return true
end

-- ====================================================================
-- 菜单点击
-- ====================================================================

local MENU_ITEM_H = 22
local MENU_W = 120
local MENU_PAD = 4

local function GetMenuItems()
    return {
        { label = "无限能量", key = "infiniteEnergy", active = M.infiniteEnergy },
        { label = "无限生命", key = "infiniteLife", active = M.infiniteLife },
        { label = "最高跳跃", key = "maxJumpNoCost", active = M.maxJumpNoCost },
        { label = "获得能力", key = "grantAbility", active = S.play.hasFireball },
    }
end

function M.HandleMenuClick(pmx, pmy)
    local items = GetMenuItems()
    -- 菜单位置：按钮左侧展开
    local menuX = btnX - MENU_W - MENU_PAD
    local menuY = btnY
    local menuH = #items * MENU_ITEM_H + MENU_PAD * 2

    -- 如果菜单超出左边界，改为右侧展开
    if menuX < 0 then
        menuX = btnX + BTN_SIZE + MENU_PAD
    end
    -- 如果菜单超出下边界，向上调整
    if menuY + menuH > S.playViewH then
        menuY = S.playViewH - menuH
    end

    if pmx < menuX or pmx > menuX + MENU_W or pmy < menuY or pmy > menuY + menuH then
        return false
    end

    local idx = math.floor((pmy - menuY - MENU_PAD) / MENU_ITEM_H) + 1
    if idx >= 1 and idx <= #items then
        local item = items[idx]
        if item.key == "infiniteEnergy" then
            M.infiniteEnergy = not M.infiniteEnergy
        elseif item.key == "infiniteLife" then
            M.infiniteLife = not M.infiniteLife
        elseif item.key == "maxJumpNoCost" then
            M.maxJumpNoCost = not M.maxJumpNoCost
        elseif item.key == "grantAbility" then
            -- 一次性给予火球能力
            S.play.hasFireball = true
            S.SetMessage("GM: 已获得火球能力!", 1.5)
        end
        return true
    end
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
        -- 让 CalcJump 返回最大值（通过设置 fallGridCount 为一个大数）
        -- maxJumpGrids = 0 表示无上限，所以我们设一个安全的大值
        local maxJump = S.playerParams.maxJumpGrids
        if maxJump <= 0 then maxJump = 50 end
        -- 反推需要的 fallGridCount: jump = baseJump + fallGridCount * multiplier
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
-- 渲染（NanoVG，在 play view 坐标系下）
-- ====================================================================

function M.Draw(vg)
    if not M.IsActive() then return end
    M.DrawButton(vg)
    if M.menuOpen then
        M.DrawMenu(vg)
    end
end

function M.DrawButton(vg)
    -- 输入空间 → NanoVG 本地空间（乘 zoom）
    local zoom = S.playerParams.cameraZoom or 1.0
    local dx = btnX * zoom
    local dy = btnY * zoom
    local ds = BTN_SIZE * zoom

    -- 按钮背景（圆角矩形）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx, dy, ds, ds, 4 * zoom)

    -- 有任何 GM 开关激活时高亮
    local anyActive = M.infiniteEnergy or M.infiniteLife or M.maxJumpNoCost
    if anyActive then
        nvgFillColor(vg, nvgRGBA(200, 50, 50, 220))
    else
        nvgFillColor(vg, nvgRGBA(60, 60, 80, 200))
    end
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx, dy, ds, ds, 4 * zoom)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 80, anyActive and 255 or 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 文字 "GM"
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10 * zoom)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgText(vg, dx + ds * 0.5, dy + ds * 0.5, "GM")
end

function M.DrawMenu(vg)
    local items = GetMenuItems()
    local zoom = S.playerParams.cameraZoom or 1.0

    -- 在输入空间计算菜单位置
    local menuX = btnX - MENU_W - MENU_PAD
    local menuY = btnY
    local menuH = #items * MENU_ITEM_H + MENU_PAD * 2

    -- 如果超出左边界，改为右侧
    if menuX < 0 then
        menuX = btnX + BTN_SIZE + MENU_PAD
    end
    -- 超出下边界则向上
    if menuY + menuH > S.playViewH then
        menuY = S.playViewH - menuH
    end

    -- 转换到 NanoVG 本地空间（乘 zoom）
    local mx = menuX * zoom
    local my = menuY * zoom
    local mw = MENU_W * zoom
    local mh = menuH * zoom
    local itemH = MENU_ITEM_H * zoom
    local pad = MENU_PAD * zoom

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mx, my, mw, mh, 4 * zoom)
    nvgFillColor(vg, nvgRGBA(20, 20, 30, 230))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mx, my, mw, mh, 4 * zoom)
    nvgStrokeColor(vg, nvgRGBA(255, 180, 80, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 菜单项
    nvgFontFace(vg, "sans")
    for i, item in ipairs(items) do
        local iy = my + pad + (i - 1) * itemH
        local isActive = item.active

        -- 悬停/选中背景
        if isActive then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, mx + 2 * zoom, iy + 1 * zoom, mw - 4 * zoom, itemH - 2 * zoom, 3 * zoom)
            nvgFillColor(vg, nvgRGBA(80, 160, 80, 100))
            nvgFill(vg)
        end

        -- 开关指示器（小圆点）
        local dotX = mx + 12 * zoom
        local dotY = iy + itemH * 0.5
        nvgBeginPath(vg)
        nvgCircle(vg, dotX, dotY, 4 * zoom)
        if isActive then
            nvgFillColor(vg, nvgRGBA(80, 255, 80, 255))
        else
            nvgFillColor(vg, nvgRGBA(100, 100, 100, 200))
        end
        nvgFill(vg)

        -- 标签文本
        nvgFontSize(vg, 10 * zoom)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(200, 255, 200, 255))
        else
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
        end
        nvgText(vg, mx + 22 * zoom, dotY, item.label)
    end
end

return M
