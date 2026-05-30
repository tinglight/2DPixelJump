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
        { id = "bg",       label = "背景", x = 0, y = 0, w = 38, h = 14, shape = M.BTN_SHAPE_PILL, group = M.BTN_GROUP_CONFIG, hasSubmenu = true },
        { id = "fog",      label = "迷雾", x = 0, y = 0, w = 34, h = 14, shape = M.BTN_SHAPE_PILL, group = M.BTN_GROUP_CONFIG },
        { id = "gizmos",   label = "标记", x = 0, y = 0, w = 34, h = 14, shape = M.BTN_SHAPE_PILL, group = M.BTN_GROUP_CONFIG },
        { id = "random",   label = "随机", x = 0, y = 0, w = 34, h = 14, shape = M.BTN_SHAPE_ROUNDED, group = M.BTN_GROUP_MODE },
        { id = "worldmap", label = "世界", x = 0, y = 0, w = 34, h = 14, shape = M.BTN_SHAPE_ROUNDED, group = M.BTN_GROUP_MODE, hasSubmenu = true },
        { id = "sidebar",  label = "关卡", x = 0, y = 0, w = 34, h = 14, shape = M.BTN_SHAPE_ROUNDED, group = M.BTN_GROUP_MODE },
        { id = "export",   label = "导出", x = 0, y = 0, w = 34, h = 14, shape = M.BTN_SHAPE_ROUNDED, group = M.BTN_GROUP_FILE },
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
    elseif btn.id == "bg" then
        isActive = (S.backgroundImage ~= "")
        if isActive then
            bgR, bgG, bgB = 50, 80, 60
            borderR, borderG, borderB, borderA = 80, 160, 100, 220
            textR, textG, textB = 160, 255, 180
        else
            bgR, bgG, bgB = 40, 50, 45
            borderR, borderG, borderB = 70, 90, 75
        end
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
    elseif btn.id == "gizmos" then
        isActive = S.showGizmos
        if isActive then
            bgR, bgG, bgB = 60, 90, 55
            borderR, borderG, borderB, borderA = 100, 180, 90, 220
            textR, textG, textB = 170, 240, 160
        else
            bgR, bgG, bgB = 35, 45, 38
            borderR, borderG, borderB = 60, 75, 60
            textR, textG, textB = 130, 140, 130
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
    elseif btn.id == "export" then
        bgR, bgG, bgB = 50, 70, 100
        borderR, borderG, borderB = 80, 120, 180
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

    -- 右侧：版本号 + 当前模式信息
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)

    -- 版本号（最右侧）
    nvgFillColor(vg, nvgRGBA(100, 105, 120, 180))
    nvgText(vg, S.screenDesignW - 6, centerY, "v" .. C.VERSION)

    -- 当前模式信息（版本号左侧）
    local versionW = nvgTextBounds(vg, 0, 0, "v" .. C.VERSION) + 8
    if S.editorMode == C.MODE_WORLDMAP then
        nvgFillColor(vg, nvgRGBA(160, 165, 180, 200))
        nvgText(vg, S.screenDesignW - 6 - versionW, centerY, "世界地图模式")
    else
        nvgFillColor(vg, nvgRGBA(200, 200, 210, 200))
        nvgText(vg, S.screenDesignW - 6 - versionW, centerY, "工具:" .. C.TOOLS[S.currentTool].name)
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
-- 工具栏布局常量
-- ====================================================================
M.TOOL_BTN_W = 36
M.TOOL_BTN_H = 28
M.TOOL_BTN_PAD = 4
M.EDIT_BTN_W = 20       -- 编辑按钮宽度
M.EDIT_BTN_H = 14       -- 编辑按钮高度
M.EDIT_BTN_GAP = 4      -- 编辑按钮与工具区的间距

-- ====================================================================
-- GetToolOrder - 获取当前工具显示顺序（隐藏子菜单中非代表工具）
-- ====================================================================
function M.GetToolOrder()
    local rawOrder
    if S.toolbarEditMode and S.toolOrderPending then
        rawOrder = S.toolOrderPending
    elseif S.toolOrder then
        rawOrder = S.toolOrder
    else
        rawOrder = {}
        for i = 1, #C.TOOLS do rawOrder[i] = i end
    end

    -- 子菜单折叠：每个子菜单组只保留一个代表工具（当前选中的，或首个）
    local shownSubmenuTool = {}  -- groupId -> toolIdx（本组要展示的代表）
    for _, groupDef in pairs(C.SUBMENU_GROUPS) do
        -- 如果当前选中的工具属于该组，则展示它；否则展示组内第一个
        local rep = groupDef.tools[1]
        for _, tIdx in ipairs(groupDef.tools) do
            if tIdx == S.currentTool then
                rep = tIdx
                break
            end
        end
        for _, tIdx in ipairs(groupDef.tools) do
            shownSubmenuTool[tIdx] = rep
        end
    end

    local filtered = {}
    for _, toolIdx in ipairs(rawOrder) do
        local tool = C.TOOLS[toolIdx]
        if tool and tool.submenu then
            -- 只保留代表工具
            if shownSubmenuTool[toolIdx] == toolIdx then
                filtered[#filtered + 1] = toolIdx
            end
        else
            filtered[#filtered + 1] = toolIdx
        end
    end
    return filtered
end

-- ====================================================================
-- GetToolOrderRaw - 获取原始（未折叠）顺序，用于编辑模式
-- ====================================================================
function M.GetToolOrderRaw()
    if S.toolbarEditMode and S.toolOrderPending then
        return S.toolOrderPending
    end
    if S.toolOrder then
        return S.toolOrder
    end
    local order = {}
    for i = 1, #C.TOOLS do order[i] = i end
    return order
end

-- ====================================================================
-- GetToolbarVisibleWidth - 工具栏可视区域宽度（最多显示6.5个按钮）
-- ====================================================================
function M.GetToolbarVisibleWidth()
    local btnW = M.TOOL_BTN_W
    local btnPad = M.TOOL_BTN_PAD
    return 6.5 * (btnW + btnPad) - btnPad
end

-- ====================================================================
-- GetToolbarTotalWidth - 工具栏总内容宽度
-- ====================================================================
function M.GetToolbarTotalWidth()
    local order = M.GetToolOrder()
    local btnW = M.TOOL_BTN_W
    local btnPad = M.TOOL_BTN_PAD
    return #order * (btnW + btnPad) - btnPad
end

-- ====================================================================
-- GetToolbarMaxScroll - 最大滑动偏移（负值）
-- ====================================================================
function M.GetToolbarMaxScroll()
    local totalW = M.GetToolbarTotalWidth()
    local visibleW = M.GetToolbarVisibleWidth()
    if totalW <= visibleW then return 0 end
    return -(totalW - visibleW)
end

-- ====================================================================
-- GetToolbarStartX - 工具按钮区域起始X（编辑按钮右侧）
-- ====================================================================
function M.GetToolbarStartX()
    -- 交互模式按钮占据左侧 (6 + 20 + 4 = 30px)
    -- 编辑按钮在交互模式右侧
    return 6 + 20 + M.EDIT_BTN_GAP + M.EDIT_BTN_W + M.EDIT_BTN_GAP
end

-- ====================================================================
-- DrawToolButtons - 支持左右滑动的水平工具按钮
-- ====================================================================
function M.DrawToolButtons(vg, barY, toolBarH)
    local btnW = M.TOOL_BTN_W
    local btnH = M.TOOL_BTN_H
    local btnPad = M.TOOL_BTN_PAD
    local order = M.GetToolOrder()

    local visibleW = M.GetToolbarVisibleWidth()
    local areaStartX = M.GetToolbarStartX()
    local btnY = barY + (toolBarH - btnH) * 0.5

    -- 裁剪区域：只在可视范围内绘制工具按钮
    nvgSave(vg)
    nvgScissor(vg, areaStartX, barY, visibleW, toolBarH)

    local scrollX = S.toolbarScrollX

    for slotIdx, toolIdx in ipairs(order) do
        local tool = C.TOOLS[toolIdx]
        if not tool then goto continue end

        local bx = areaStartX + (slotIdx - 1) * (btnW + btnPad) + scrollX

        -- 编辑模式下被拖拽的工具跟随鼠标
        if S.toolbarEditMode and S.toolEditDragging and slotIdx == S.toolEditDragIndex then
            bx = bx + S.toolEditDragOffsetX
        end

        -- 跳过不可见的按钮
        if bx + btnW < areaStartX - 10 or bx > areaStartX + visibleW + 10 then
            goto continue
        end

        -- 分组颜色色带
        local gc = C.GetToolGroupColor(tool)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, btnY + btnH - 3, btnW, 3, 1)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], toolIdx == S.currentTool and 255 or 120))
        nvgFill(vg)

        -- 选中高亮边框（非编辑模式时显示）
        if not S.toolbarEditMode and toolIdx == S.currentTool then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx - 2, btnY - 2, btnW + 4, btnH + 4, 5)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgStrokeWidth(vg, 2)
            nvgStroke(vg)
        end

        -- 编辑模式下被拖拽的工具半透明
        local bgAlpha = toolIdx == S.currentTool and 255 or 120
        if S.toolbarEditMode and S.toolEditDragging and slotIdx == S.toolEditDragIndex then
            bgAlpha = 200
        end

        -- 按钮背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, btnY, btnW, btnH - 3, 3)
        local c = tool.color
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], bgAlpha))
        nvgFill(vg)

        -- 编辑模式下显示拖拽手柄样式
        if S.toolbarEditMode then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, btnY, btnW, btnH - 3, 3)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 80))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- 工具名称
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
        nvgText(vg, bx + btnW * 0.5, btnY + (btnH - 3) * 0.5 - 2, tool.name)

        -- 快捷键编号（显示槽位号）
        nvgFontSize(vg, 7)
        nvgFillColor(vg, nvgRGBA(200, 200, 200, 150))
        nvgText(vg, bx + btnW * 0.5, btnY + (btnH - 3) * 0.5 + 7, tostring(slotIdx))

        -- 子菜单指示三角（右上角小三角）
        if tool.submenu and not S.toolbarEditMode then
            local triX = bx + btnW - 6
            local triY = btnY + 4
            nvgBeginPath(vg)
            nvgMoveTo(vg, triX - 3, triY)
            nvgLineTo(vg, triX + 3, triY)
            nvgLineTo(vg, triX, triY + 3)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
            nvgFill(vg)
        end

        ::continue::
    end

    nvgRestore(vg)

    -- 绘制编辑按钮
    M.DrawEditButton(vg, barY, toolBarH)
end

-- ====================================================================
-- DrawEditButton - 绘制编辑按钮（交互模式按钮右侧）
-- ====================================================================
function M.DrawEditButton(vg, barY, toolBarH)
    local editBtnX = 6 + 20 + M.EDIT_BTN_GAP  -- 交互模式右侧
    local editBtnY = barY + (toolBarH - M.EDIT_BTN_H) * 0.5 - (S.toolbarEditMode and 8 or 0)
    local ebW = M.EDIT_BTN_W
    local ebH = M.EDIT_BTN_H

    -- 编辑按钮背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, editBtnX, editBtnY, ebW, ebH, 3)
    if S.toolbarEditMode then
        nvgFillColor(vg, nvgRGBA(60, 130, 220, 255))
    else
        nvgFillColor(vg, nvgRGBA(50, 55, 70, 255))
    end
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, editBtnX, editBtnY, ebW, ebH, 3)
    nvgStrokeColor(vg, nvgRGBA(90, 100, 130, 180))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    -- 编辑图标：绘制铅笔形状
    local cx = editBtnX + ebW * 0.5
    local cy = editBtnY + ebH * 0.5
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, math.rad(-45))
    -- 笔身
    nvgBeginPath(vg)
    nvgRect(vg, -1.5, -5, 3, 7)
    nvgFillColor(vg, nvgRGBA(220, 220, 240, 255))
    nvgFill(vg)
    -- 笔尖
    nvgBeginPath(vg)
    nvgMoveTo(vg, -1.5, 2)
    nvgLineTo(vg, 1.5, 2)
    nvgLineTo(vg, 0, 4.5)
    nvgClosePath(vg)
    nvgFill(vg)
    nvgRestore(vg)

    -- 编辑模式下，在编辑按钮下方显示确认(√)按钮
    if S.toolbarEditMode then
        local confirmY = editBtnY + ebH + 3
        nvgBeginPath(vg)
        nvgRoundedRect(vg, editBtnX, confirmY, ebW, ebH, 3)
        nvgFillColor(vg, nvgRGBA(40, 160, 80, 255))
        nvgFill(vg)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, editBtnX, confirmY, ebW, ebH, 3)
        nvgStrokeColor(vg, nvgRGBA(60, 200, 100, 200))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)

        -- 打勾图标
        local ccx = editBtnX + ebW * 0.5
        local ccy = confirmY + ebH * 0.5
        nvgBeginPath(vg)
        nvgMoveTo(vg, ccx - 4, ccy)
        nvgLineTo(vg, ccx - 1, ccy + 3)
        nvgLineTo(vg, ccx + 4, ccy - 3)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgStrokeWidth(vg, 2)
        nvgLineCap(vg, NVG_ROUND)
        nvgLineJoin(vg, NVG_ROUND)
        nvgStroke(vg)
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
-- 回收站按钮布局常量
local TRASH_BTN_W = 38
local TRASH_BTN_H = 14
local TRASH_BTN_MARGIN = 6

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

    -- 回收站按钮（右下角，状态栏上方）
    M.DrawTrashButton(vg)
end

--- 绘制回收站按钮（底部工具栏右下方）
function M.DrawTrashButton(vg)
    local statusH = 16
    local btnX = S.screenDesignW - TRASH_BTN_W - TRASH_BTN_MARGIN
    local btnY = S.screenDesignH - statusH - TRASH_BTN_H - 4

    -- 存储位置供命中检测使用
    S.trashBtnRect = { x = btnX, y = btnY, w = TRASH_BTN_W, h = TRASH_BTN_H }

    -- 检查是否有回收站内容
    local CloudStorage = require "CloudStorage"
    local trashList = CloudStorage.ListTrash()
    local hasItems = #trashList > 0

    -- 鼠标悬停检测
    local mx = input:GetMousePosition().x / S.dpr / S.scaleF
    local my = input:GetMousePosition().y / S.dpr / S.scaleF
    local isHover = mx >= btnX and mx < btnX + TRASH_BTN_W and my >= btnY and my < btnY + TRASH_BTN_H

    -- 按钮背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, TRASH_BTN_W, TRASH_BTN_H, 3)
    if isHover then
        nvgFillColor(vg, nvgRGBA(80, 60, 60, 240))
    else
        nvgFillColor(vg, nvgRGBA(45, 35, 45, 220))
    end
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, TRASH_BTN_W, TRASH_BTN_H, 3)
    nvgStrokeColor(vg, hasItems and nvgRGBA(200, 100, 80, 180) or nvgRGBA(80, 80, 100, 150))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    -- 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, hasItems and nvgRGBA(255, 140, 120, 255) or nvgRGBA(150, 150, 160, 200))
    local label = "回收站"
    if hasItems then
        label = "回收站(" .. #trashList .. ")"
    end
    nvgText(vg, btnX + TRASH_BTN_W * 0.5, btnY + TRASH_BTN_H * 0.5, label)
end

--- 命中检测：回收站按钮
---@param mx number
---@param my number
---@return boolean
function M.HitTestTrashButton(mx, my)
    if not S.trashBtnRect then return false end
    local r = S.trashBtnRect
    return mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
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

---@return number|nil 命中的槽位索引(1-based)
function M.HitTestToolbar(mx, my)
    local toolBarH = C.BOTTOMBAR_H
    local barY = S.screenDesignH - toolBarH - 16
    if my < barY or my > barY + toolBarH then return nil end

    local btnW = M.TOOL_BTN_W
    local btnH = M.TOOL_BTN_H
    local btnPad = M.TOOL_BTN_PAD
    local order = M.GetToolOrder()
    local areaStartX = M.GetToolbarStartX()
    local visibleW = M.GetToolbarVisibleWidth()
    local btnY = barY + (toolBarH - btnH) * 0.5
    local scrollX = S.toolbarScrollX

    -- 只在可视区域内命中
    if mx < areaStartX or mx > areaStartX + visibleW then return nil end

    for slotIdx = 1, #order do
        local bx = areaStartX + (slotIdx - 1) * (btnW + btnPad) + scrollX
        if mx >= bx and mx < bx + btnW and my >= btnY and my < btnY + btnH then
            return slotIdx
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

---@return string|nil "edit" 或 "confirm" 或 nil
function M.HitTestEditButtons(mx, my)
    local toolBarH = C.BOTTOMBAR_H
    local barY = S.screenDesignH - toolBarH - 16
    if my < barY or my > barY + toolBarH then return nil end

    local editBtnX = 6 + 20 + M.EDIT_BTN_GAP
    local editBtnY = barY + (toolBarH - M.EDIT_BTN_H) * 0.5 - (S.toolbarEditMode and 8 or 0)
    local ebW = M.EDIT_BTN_W
    local ebH = M.EDIT_BTN_H

    -- 编辑按钮
    if mx >= editBtnX and mx < editBtnX + ebW and my >= editBtnY and my < editBtnY + ebH then
        return "edit"
    end

    -- 确认按钮（仅编辑模式下可见）
    if S.toolbarEditMode then
        local confirmY = editBtnY + ebH + 3
        if mx >= editBtnX and mx < editBtnX + ebW and my >= confirmY and my < confirmY + ebH then
            return "confirm"
        end
    end

    return nil
end

---@return boolean 鼠标是否在工具栏可滑动区域内
function M.HitTestToolbarArea(mx, my)
    local toolBarH = C.BOTTOMBAR_H
    local barY = S.screenDesignH - toolBarH - 16
    if my < barY or my > barY + toolBarH then return false end
    local areaStartX = M.GetToolbarStartX()
    local visibleW = M.GetToolbarVisibleWidth()
    return mx >= areaStartX and mx < areaStartX + visibleW
end

-- ====================================================================
-- DrawSubmenuPopup - 绘制子菜单展开弹出层
-- ====================================================================
function M.DrawSubmenuPopup()
    if not S.submenuOpen or not S.submenuGroupId then return end
    local group = C.SUBMENU_GROUPS[S.submenuGroupId]
    if not group then return end

    local vg = S.vg
    local toolBarH = C.BOTTOMBAR_H
    local barY = S.screenDesignH - toolBarH - 16

    -- 计算弹出位置：在触发按钮的正上方
    local btnW = M.TOOL_BTN_W
    local btnH = M.TOOL_BTN_H
    local btnPad = M.TOOL_BTN_PAD
    local popupBtnW = 38
    local popupBtnH = 24
    local popupPad = 4
    local numItems = #group.tools
    local popupW = numItems * (popupBtnW + popupPad) - popupPad + 12  -- 12=padding
    local popupH = popupBtnH + 16  -- 16=top+bottom padding

    -- 锚点X：基于触发槽位在工具栏中的实际位置
    local order = M.GetToolOrder()
    local areaStartX = M.GetToolbarStartX()
    local scrollX = S.toolbarScrollX
    local anchorX = areaStartX  -- 默认
    for slotIdx, toolIdx in ipairs(order) do
        local tool = C.TOOLS[toolIdx]
        if tool and tool.submenu == S.submenuGroupId then
            anchorX = areaStartX + (slotIdx - 1) * (btnW + btnPad) + scrollX + btnW * 0.5
            break
        end
    end

    local popupX = anchorX - popupW * 0.5
    -- 边界约束
    popupX = math.max(4, math.min(S.screenDesignW - popupW - 4, popupX))
    local popupY = barY - popupH - 4

    -- 保存弹出层位置供命中检测使用
    S.submenuPopupX = popupX
    S.submenuPopupY = popupY
    S.submenuPopupW = popupW
    S.submenuPopupH = popupH

    -- 绘制弹出背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, popupX, popupY, popupW, popupH, 6)
    nvgFillColor(vg, nvgRGBA(25, 28, 40, 240))
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, popupX, popupY, popupW, popupH, 6)
    nvgStrokeColor(vg, nvgRGBA(80, 90, 120, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 底部指示三角（指向工具栏）
    local triCx = anchorX
    triCx = math.max(popupX + 10, math.min(popupX + popupW - 10, triCx))
    nvgBeginPath(vg)
    nvgMoveTo(vg, triCx - 5, popupY + popupH)
    nvgLineTo(vg, triCx + 5, popupY + popupH)
    nvgLineTo(vg, triCx, popupY + popupH + 4)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(25, 28, 40, 240))
    nvgFill(vg)

    -- 绘制子选项按钮
    local startBtnX = popupX + 6
    local btnStartY = popupY + 8
    nvgFontFace(vg, "sans")

    for i, toolIdx in ipairs(group.tools) do
        local tool = C.TOOLS[toolIdx]
        if not tool then goto continue_sub end
        local bx = startBtnX + (i - 1) * (popupBtnW + popupPad)
        local by = btnStartY
        local isSelected = (toolIdx == S.currentTool)

        -- 选中高亮
        if isSelected then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx - 2, by - 2, popupBtnW + 4, popupBtnH + 4, 5)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        -- 按钮背景
        local c = tool.color
        local alpha = isSelected and 255 or 180
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, popupBtnW, popupBtnH, 4)
        nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], alpha))
        nvgFill(vg)

        -- 工具名
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, bx + popupBtnW * 0.5, by + popupBtnH * 0.5, tool.name)

        ::continue_sub::
    end
end

-- ====================================================================
-- HitTestSubmenuPopup - 检测子菜单弹出层点击
-- ====================================================================
---@return number|nil 命中的工具索引（C.TOOLS 中的索引）
function M.HitTestSubmenuPopup(mx, my)
    if not S.submenuOpen or not S.submenuGroupId then return nil end
    local group = C.SUBMENU_GROUPS[S.submenuGroupId]
    if not group then return nil end

    local popupX = S.submenuPopupX or 0
    local popupY = S.submenuPopupY or 0
    local popupW = S.submenuPopupW or 0
    local popupH = S.submenuPopupH or 0

    -- 先检查是否在弹出层区域内
    if mx < popupX or mx > popupX + popupW or my < popupY or my > popupY + popupH then
        return nil
    end

    -- 检测各子选项按钮
    local popupBtnW = 38
    local popupBtnH = 24
    local popupPad = 4
    local startBtnX = popupX + 6
    local btnStartY = popupY + 8

    for i, toolIdx in ipairs(group.tools) do
        local bx = startBtnX + (i - 1) * (popupBtnW + popupPad)
        local by = btnStartY
        if mx >= bx and mx < bx + popupBtnW and my >= by and my < by + popupBtnH then
            return toolIdx
        end
    end
    return nil  -- 在弹出层内但未命中按钮
end

-- ====================================================================
-- IsInsideSubmenuPopup - 检测点击是否在子菜单弹出层区域内（含三角）
-- ====================================================================
function M.IsInsideSubmenuPopup(mx, my)
    if not S.submenuOpen then return false end
    local popupX = S.submenuPopupX or 0
    local popupY = S.submenuPopupY or 0
    local popupW = S.submenuPopupW or 0
    local popupH = S.submenuPopupH or 0
    -- 扩大点区域（含三角和少量margin）
    return mx >= popupX - 2 and mx <= popupX + popupW + 2
       and my >= popupY - 2 and my <= popupY + popupH + 6
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
