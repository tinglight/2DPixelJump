-- ====================================================================
-- editor/Toolbar.lua - 顶栏、底部工具栏、状态栏渲染
-- ====================================================================

local C = require "editor.Constants"
local S = require "editor.State"

local M = {}

-- ====================================================================
-- 按钮形状/分组常量
-- ====================================================================
M.BTN_SHAPE_CIRCLE  = "circle"
M.BTN_SHAPE_PILL    = "pill"
M.BTN_SHAPE_ROUNDED = "rounded"

M.BTN_GROUP_PLAY   = "play"
M.BTN_GROUP_FILE   = "file"
M.BTN_GROUP_CONFIG = "config"
M.BTN_GROUP_MODE   = "mode"

-- ====================================================================
-- 交互模式定义
-- ====================================================================
local INTERACT_MODES = {
    { id = C.INTERACT_DRAW,   icon = "✎", label = "绘制", key = "R" },
    { id = C.INTERACT_SELECT, icon = "⊙", label = "选取", key = "Q" },
    { id = C.INTERACT_MOVE,   icon = "✥", label = "移动", key = "E" },
}

-- ====================================================================
-- InitTopBarButtons - 初始化顶栏按钮定义
-- ====================================================================
function M.InitTopBarButtons()
    S.topBarButtons = {
        { id = "play",     label = "▶",   x = 0, y = 0, w = 18, h = 18, shape = M.BTN_SHAPE_CIRCLE,  group = M.BTN_GROUP_PLAY },
        { id = "save",     label = "保存", x = 0, y = 0, w = 34, h = 14, shape = M.BTN_SHAPE_ROUNDED, group = M.BTN_GROUP_FILE },
        { id = "saveNew",  label = "另存", x = 0, y = 0, w = 34, h = 14, shape = M.BTN_SHAPE_ROUNDED, group = M.BTN_GROUP_FILE },
        { id = "canvas",   label = "画布", x = 0, y = 0, w = 38, h = 14, shape = M.BTN_SHAPE_PILL, group = M.BTN_GROUP_CONFIG, hasSubmenu = true },
        { id = "player",   label = "玩家", x = 0, y = 0, w = 38, h = 14, shape = M.BTN_SHAPE_PILL, group = M.BTN_GROUP_CONFIG, hasSubmenu = true },
        { id = "fog",      label = "迷雾", x = 0, y = 0, w = 34, h = 14, shape = M.BTN_SHAPE_PILL, group = M.BTN_GROUP_CONFIG },
        { id = "random",   label = "随机", x = 0, y = 0, w = 34, h = 14, shape = M.BTN_SHAPE_ROUNDED, group = M.BTN_GROUP_MODE },
        { id = "worldmap", label = "世界", x = 0, y = 0, w = 34, h = 14, shape = M.BTN_SHAPE_ROUNDED, group = M.BTN_GROUP_MODE, hasSubmenu = true },
        { id = "sidebar",  label = "关卡", x = 0, y = 0, w = 34, h = 14, shape = M.BTN_SHAPE_ROUNDED, group = M.BTN_GROUP_MODE },
    }
end

-- ====================================================================
-- 内部：绘制下拉三角标识
-- ====================================================================
local function DrawSubmenuTriangle(vg, cx, cy, size)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - size * 0.5, cy - size * 0.3)
    nvgLineTo(vg, cx + size * 0.5, cy - size * 0.3)
    nvgLineTo(vg, cx, cy + size * 0.5)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 180))
    nvgFill(vg)
end

-- ====================================================================
-- 内部：获取顶栏按钮颜色
-- ====================================================================
local function GetButtonColors(btn)
    local bgR, bgG, bgB, bgA = 45, 50, 65, 255
    local borderR, borderG, borderB, borderA = 80, 85, 100, 150
    local textR, textG, textB = 230, 230, 240
    local isActive = false

    if btn.id == "play" then
        bgR, bgG, bgB = 30, 160, 90
        borderR, borderG, borderB, borderA = 50, 200, 120, 200
        textR, textG, textB = 255, 255, 255
    elseif btn.id == "save" then
        bgR, bgG, bgB = 45, 100, 65
        borderR, borderG, borderB = 70, 140, 90
    elseif btn.id == "saveNew" then
        bgR, bgG, bgB = 50, 80, 70
        borderR, borderG, borderB = 70, 120, 90
    elseif btn.id == "canvas" then
        bgR, bgG, bgB = 60, 75, 90
        borderR, borderG, borderB = 90, 110, 140
    elseif btn.id == "player" then
        bgR, bgG, bgB = 75, 65, 50
        borderR, borderG, borderB = 130, 110, 70
    elseif btn.id == "fog" then
        isActive = S.fogShowInEditor
        if isActive then
            bgR, bgG, bgB = 50, 55, 110
            borderR, borderG, borderB, borderA = 90, 100, 200, 220
            textR, textG, textB = 160, 180, 255
        else
            bgR, bgG, bgB = 35, 38, 55
            borderR, borderG, borderB = 60, 65, 80
            textR, textG, textB = 140, 140, 160
        end
    elseif btn.id == "random" then
        bgR, bgG, bgB = 100, 60, 35
        borderR, borderG, borderB = 160, 100, 50
    elseif btn.id == "worldmap" then
        isActive = (S.editorMode == C.MODE_WORLDMAP)
        if isActive then
            bgR, bgG, bgB = 90, 45, 110
            borderR, borderG, borderB, borderA = 150, 80, 200, 220
        else
            bgR, bgG, bgB = 55, 40, 70
            borderR, borderG, borderB = 90, 65, 120
        end
    elseif btn.id == "sidebar" then
        isActive = S.sidebarOpen
        if isActive then
            bgR, bgG, bgB = 70, 60, 45
            borderR, borderG, borderB, borderA = 130, 110, 70, 200
        else
            bgR, bgG, bgB = 45, 42, 38
            borderR, borderG, borderB = 80, 70, 60
        end
    end

    return bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA, textR, textG, textB, isActive
end

-- ====================================================================
-- 内部：绘制圆形按钮
-- ====================================================================
local function DrawCircleButton(vg, btn, curX, centerY, btnGap, colors)
    local bgR, bgG, bgB, _, borderR, borderG, borderB, borderA, textR, textG, textB = table.unpack(colors)
    local radius = btn.w * 0.5
    local cx = curX + radius
    local cy = centerY
    btn.x = curX
    btn.y = cy - radius
    btn.w = radius * 2
    btn.h = radius * 2

    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius + 2)
    nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, 60))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius)
    local paint = nvgRadialGradient(vg, cx, cy - 2, 1, radius,
        nvgRGBA(bgR + 30, bgG + 30, bgB + 30, 255),
        nvgRGBA(bgR, bgG, bgB, 255))
    nvgFillPaint(vg, paint)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, radius)
    nvgStrokeColor(vg, nvgRGBA(borderR, borderG, borderB, borderA))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(textR, textG, textB, 255))
    nvgText(vg, cx + 1, cy, btn.label)

    return curX + btn.w + btnGap
end

-- ====================================================================
-- 内部：绘制药丸形按钮
-- ====================================================================
local function DrawPillButton(vg, btn, curX, centerY, btnGap, colors)
    local bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA, textR, textG, textB = table.unpack(colors)
    local bw, bh = btn.w, btn.h
    local bx = curX
    local by = centerY - bh * 0.5
    btn.x = bx
    btn.y = by

    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, bw, bh, bh * 0.5)
    nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, bgA))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, bw, bh, bh * 0.5)
    nvgStrokeColor(vg, nvgRGBA(borderR, borderG, borderB, borderA))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    local textOffsetX = btn.hasSubmenu and -3 or 0
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(textR, textG, textB, 255))
    nvgText(vg, bx + bw * 0.5 + textOffsetX, by + bh * 0.5, btn.label)

    if btn.hasSubmenu then
        DrawSubmenuTriangle(vg, bx + bw - 8, by + bh * 0.5, 5)
    end

    return curX + bw + btnGap
end

-- ====================================================================
-- 内部：绘制圆角矩形按钮
-- ====================================================================
local function DrawRoundedButton(vg, btn, curX, centerY, btnGap, colors, isActive)
    local bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA, textR, textG, textB = table.unpack(colors)
    local bw, bh = btn.w, btn.h
    local bx = curX
    local by = centerY - bh * 0.5
    btn.x = bx
    btn.y = by

    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, bw, bh, 4)
    nvgFillColor(vg, nvgRGBA(bgR, bgG, bgB, bgA))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx, by, bw, bh, 4)
    nvgStrokeColor(vg, nvgRGBA(borderR, borderG, borderB, borderA))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    if isActive then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx + 2, by, bw - 4, 2, 1)
        nvgFillColor(vg, nvgRGBA(borderR, borderG, borderB, 200))
        nvgFill(vg)
    end

    local textOffsetX = btn.hasSubmenu and -3 or 0
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(textR, textG, textB, 255))
    nvgText(vg, bx + bw * 0.5 + textOffsetX, by + bh * 0.5, btn.label)

    if btn.hasSubmenu then
        DrawSubmenuTriangle(vg, bx + bw - 7, by + bh * 0.5, 4.5)
    end

    return curX + bw + btnGap
end

-- ====================================================================
-- DrawTopBar - 绘制顶栏
-- ====================================================================
function M.DrawTopBar()
    local vg = S.vg

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, S.screenDesignW, C.TOPBAR_H)
    nvgFillPaint(vg, nvgLinearGradient(vg, 0, 0, 0, C.TOPBAR_H,
        nvgRGBA(28, 28, 40, 250), nvgRGBA(18, 18, 28, 250)))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, C.TOPBAR_H - 0.5)
    nvgLineTo(vg, S.screenDesignW, C.TOPBAR_H - 0.5)
    nvgStrokeColor(vg, nvgRGBA(60, 65, 80, 200))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")

    local curX = 4
    local centerY = C.TOPBAR_H * 0.5
    local groupGap = 10
    local btnGap = 3
    local lastGroup = nil

    for _, btn in ipairs(S.topBarButtons) do
        if lastGroup and btn.group ~= lastGroup then
            curX = curX + groupGap
            nvgBeginPath(vg)
            nvgCircle(vg, curX - groupGap * 0.5, centerY, 1.2)
            nvgFillColor(vg, nvgRGBA(80, 85, 100, 150))
            nvgFill(vg)
        end
        lastGroup = btn.group

        local bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA, textR, textG, textB, isActive = GetButtonColors(btn)
        local colors = {bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA, textR, textG, textB}

        if btn.shape == M.BTN_SHAPE_CIRCLE then
            curX = DrawCircleButton(vg, btn, curX, centerY, btnGap, colors)
        elseif btn.shape == M.BTN_SHAPE_PILL then
            curX = DrawPillButton(vg, btn, curX, centerY, btnGap, colors)
        else
            curX = DrawRoundedButton(vg, btn, curX, centerY, btnGap, colors, isActive)
        end
    end

    -- 右侧当前模式信息
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    if S.editorMode == C.MODE_WORLDMAP then
        nvgFillColor(vg, nvgRGBA(160, 165, 180, 200))
        nvgText(vg, S.screenDesignW - 6, centerY, "世界地图模式")
    else
        nvgFillColor(vg, nvgRGBA(200, 200, 210, 200))
        nvgText(vg, S.screenDesignW - 6, centerY, "工具:" .. C.TOOLS[S.currentTool].name)
    end
end

-- ====================================================================
-- DrawToolbar - 绘制底部工具栏（交互模式+工具按钮+颜色分组）
-- ====================================================================
function M.DrawToolbar()
    local vg = S.vg
    local toolBarH = C.BOTTOMBAR_H
    local barY = S.screenDesignH - toolBarH - 16  -- 16 = 状态栏高度

    -- 顶部分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, barY)
    nvgLineTo(vg, S.screenDesignW, barY)
    nvgStrokeColor(vg, nvgRGBA(80, 80, 100, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    M.DrawInteractModeButtons(vg, barY)
    M.DrawToolButtons(vg, barY, toolBarH)
    M.DrawGroupIndicator(vg, barY, toolBarH)
end

-- ====================================================================
-- DrawInteractModeButtons - 左下角交互模式切换
-- ====================================================================
function M.DrawInteractModeButtons(vg, barY)
    local modeBtnW = 20
    local modeBtnH = 11
    local modeBtnPad = 2
    local modeBtnStartX = 6
    local modeBtnStartY = barY + 3

    for i, mode in ipairs(INTERACT_MODES) do
        local mbx = modeBtnStartX
        local mby = modeBtnStartY + (i - 1) * (modeBtnH + modeBtnPad)
        local isActive = (S.interactMode == mode.id)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, mbx, mby, modeBtnW, modeBtnH, 3)
        nvgFillColor(vg, isActive and nvgRGBA(60, 130, 220, 255) or nvgRGBA(40, 42, 55, 255))
        nvgFill(vg)

        if isActive then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, mbx - 1, mby - 1, modeBtnW + 2, modeBtnH + 2, 4)
            nvgStrokeColor(vg, nvgRGBA(100, 180, 255, 220))
            nvgStrokeWidth(vg, 1.0)
            nvgStroke(vg)
        end

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 8)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, isActive and 255 or 160))
        nvgText(vg, mbx + modeBtnW * 0.5, mby + modeBtnH * 0.5, mode.key)
    end
end

-- ====================================================================
-- DrawToolButtons - 居中水平排列的工具按钮
-- ====================================================================
function M.DrawToolButtons(vg, barY, toolBarH)
    local btnW = 36
    local btnH = 28
    local btnPad = 4
    local totalW = #C.TOOLS * (btnW + btnPad) - btnPad
    local startX = (S.screenDesignW - totalW) * 0.5
    local btnY = barY + (toolBarH - btnH) * 0.5

    for i, tool in ipairs(C.TOOLS) do
        local bx = startX + (i - 1) * (btnW + btnPad)

        -- 分组颜色色带
        local gc = C.GetToolGroupColor(tool)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, btnY + btnH - 3, btnW, 3, 1)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], i == S.currentTool and 255 or 120))
        nvgFill(vg)

        -- 选中高亮边框
        if i == S.currentTool then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx - 2, btnY - 2, btnW + 4, btnH + 4, 5)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end

        -- 按钮背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, btnY, btnW, btnH - 3, 3)
        local c = tool.color
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], i == S.currentTool and 255 or 120))
        nvgFill(vg)

        -- 工具名称
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
        nvgText(vg, bx + btnW * 0.5, btnY + (btnH - 3) * 0.5 - 2, tool.name)

        -- 快捷键编号
        nvgFontSize(vg, 7)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 150))
        nvgText(vg, bx + btnW * 0.5, btnY + (btnH - 3) * 0.5 + 7, tostring(i))
    end
end

-- ====================================================================
-- DrawGroupIndicator - 工具栏右侧颜色分组指示器
-- ====================================================================
function M.DrawGroupIndicator(vg, barY, toolBarH)
    local btnW = 36
    local btnH = 28
    local btnPad = 4
    local totalW = #C.TOOLS * (btnW + btnPad) - btnPad
    local startX = (S.screenDesignW - totalW) * 0.5
    local btnY = barY + (toolBarH - btnH) * 0.5

    local indicatorX = startX + totalW + 12
    local indicatorY = btnY + btnH * 0.5
    local sgc = C.GROUP_COLORS[S.currentGroup]

    for gi = 1, C.MAX_GROUPS do
        local gc = C.GROUP_COLORS[gi]
        local gx = indicatorX + (gi - 1) * 14
        local radius = (gi == S.currentGroup) and 6 or 4
        local alpha = (gi == S.currentGroup) and 255 or 100

        nvgBeginPath(vg)
        nvgCircle(vg, gx, indicatorY - 2, radius)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], alpha))
        nvgFill(vg)

        if gi == S.currentGroup then
            nvgBeginPath(vg)
            nvgCircle(vg, gx, indicatorY - 2, radius + 1.5)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(sgc[1], sgc[2], sgc[3], 255))
    nvgText(vg, indicatorX + C.MAX_GROUPS * 14 + 2, indicatorY - 2,
        C.GROUP_NAMES[S.currentGroup] .. " [G]")
end

-- ====================================================================
-- DrawBottomBar - 底部状态栏
-- ====================================================================
function M.DrawBottomBar()
    local vg = S.vg
    local statusH = 16
    local by = S.screenDesignH - statusH

    nvgBeginPath(vg)
    nvgRect(vg, 0, by, S.screenDesignW, statusH)
    nvgFillColor(vg, nvgRGBA(15, 15, 25, 250))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 200))

    local diffName = C.DIFFICULTY_NAMES[C.DIFFICULTIES[S.currentDifficulty]] or "普通"
    nvgText(vg, 6, by + statusH * 0.5,
        "左键:放置  右键:擦除  AD:滚动  1-7:工具  R:随机  T:难度[" .. diffName .. "]")

    if S.msgTimer > 0 then
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 255, 100, math.min(255, math.floor(S.msgTimer * 255))))
        nvgText(vg, S.screenDesignW - 6, by + statusH * 0.5, S.msgText)
    end
end

-- ====================================================================
-- 命中检测
-- ====================================================================

---@param mx number 设计坐标鼠标x
---@param my number 设计坐标鼠标y
---@return string|nil 命中的按钮 id
function M.HitTestTopBar(mx, my)
    if my > C.TOPBAR_H then return nil end
    for _, btn in ipairs(S.topBarButtons) do
        if mx >= btn.x and mx < btn.x + btn.w and my >= btn.y and my < btn.y + btn.h then
            return btn.id
        end
    end
    return nil
end

---@return number|nil 命中的工具索引(1-based)
function M.HitTestToolbar(mx, my)
    local toolBarH = C.BOTTOMBAR_H
    local barY = S.screenDesignH - toolBarH - 16
    if my < barY or my > barY + toolBarH then return nil end

    local btnW = 36
    local btnH = 28
    local btnPad = 4
    local totalW = #C.TOOLS * (btnW + btnPad) - btnPad
    local startX = (S.screenDesignW - totalW) * 0.5
    local btnY = barY + (toolBarH - btnH) * 0.5

    for i = 1, #C.TOOLS do
        local bx = startX + (i - 1) * (btnW + btnPad)
        if mx >= bx and mx < bx + btnW and my >= btnY and my < btnY + btnH then
            return i
        end
    end
    return nil
end

---@return number|nil 命中的交互模式 id
function M.HitTestInteractMode(mx, my)
    local toolBarH = C.BOTTOMBAR_H
    local barY = S.screenDesignH - toolBarH - 16
    local modeBtnW = 20
    local modeBtnH = 11
    local modeBtnPad = 2
    local modeBtnStartX = 6
    local modeBtnStartY = barY + 3

    for i, mode in ipairs(INTERACT_MODES) do
        local mbx = modeBtnStartX
        local mby = modeBtnStartY + (i - 1) * (modeBtnH + modeBtnPad)
        if mx >= mbx and mx < mbx + modeBtnW and my >= mby and my < mby + modeBtnH then
            return mode.id
        end
    end
    return nil
end

---@return number|nil 命中的颜色分组索引
function M.HitTestGroup(mx, my)
    local toolBarH = C.BOTTOMBAR_H
    local barY = S.screenDesignH - toolBarH - 16
    local btnW = 36
    local btnH = 28
    local btnPad = 4
    local totalW = #C.TOOLS * (btnW + btnPad) - btnPad
    local startX = (S.screenDesignW - totalW) * 0.5
    local btnY = barY + (toolBarH - btnH) * 0.5

    local indicatorX = startX + totalW + 12
    local indicatorY = btnY + btnH * 0.5

    for gi = 1, C.MAX_GROUPS do
        local gx = indicatorX + (gi - 1) * 14
        local dx = mx - gx
        local dy = my - (indicatorY - 2)
        if dx * dx + dy * dy <= 8 * 8 then
            return gi
        end
    end
    return nil
end

return M
