-- ====================================================================
-- editor/Dialogs.lua - 对话框系统（渲染 + 输入 + 逻辑）
-- ====================================================================

local C = require "editor.Constants"
local S = require "editor.State"
local UI = require("urhox-libs/UI")
local CloudStorage = require "CloudStorage"

local M = {}

-- ====================================================================
-- 外部依赖（通过 Inject 注入）
-- ====================================================================
local FogOfWar = nil
local MapData = nil
local Persistence = nil

function M.Inject(deps)
    FogOfWar = deps.FogOfWar
    MapData = deps.MapData
    Persistence = deps.Persistence
end

-- ====================================================================
-- UI Modal 对话框（用于重命名，支持 IME 和剪贴板）
-- ====================================================================
local renameModal_ = nil
local renameTextField_ = nil

local function DestroyRenameUI()
    if renameModal_ then
        renameModal_:Close()
        renameModal_ = nil
        renameTextField_ = nil
        UI.DisableAutoEventsInput()
    end
end

local function CreateRenameUI(initialValue)
    DestroyRenameUI()

    -- 启用 UI 库的输入事件转发，Modal 内的 Button/TextField 才能接收点击
    UI.EnableAutoEventsInput()

    renameTextField_ = UI.TextField {
        value = initialValue or "",
        placeholder = "输入关卡名...",
        width = "100%",
        onSubmit = function(self, value)
            S.renameInput = value
            M.ConfirmDialog()
        end,
    }

    renameModal_ = UI.Modal {
        title = "重命名关卡",
        size = "sm",
        closeOnEscape = true,
        closeOnOverlay = true,
        onClose = function()
            -- Modal 被用户关闭（ESC 或点击遮罩），同步取消编辑器对话框状态
            renameModal_ = nil
            renameTextField_ = nil
            S.dialogMode = nil
            S.dialogTarget = nil
            input:SetScreenKeyboardVisible(false)
            UI.DisableAutoEventsInput()
        end,
    }

    renameModal_:AddContent(renameTextField_)

    -- Footer: 取消 + 确认 按钮
    local footer = UI.Panel {
        flexDirection = "row",
        justifyContent = "flex-end",
        gap = 10,
        width = "100%",
    }
    footer:AddChild(UI.Button {
        text = "取消",
        variant = "secondary",
        onClick = function()
            M.CancelDialog()
        end,
    })
    footer:AddChild(UI.Button {
        text = "确认",
        variant = "primary",
        onClick = function()
            if renameTextField_ then
                S.renameInput = renameTextField_:GetValue() or S.renameInput
            end
            M.ConfirmDialog()
        end,
    })
    renameModal_:SetFooter(footer)

    renameModal_:Open()
end

-- ====================================================================
-- 对话框打开
-- ====================================================================

function M.OpenCanvasDialog()
    input:SetScreenKeyboardVisible(true)
    S.dialogMode = "canvas"
    S.canvasWidthInput = tostring(S.MAP_COLS)
    S.canvasHeightInput = tostring(S.MAP_ROWS)
    S.canvasFocusField = 1
    S.canvasCursor = #S.canvasWidthInput
    S.renameBlink = 0
    S.imeComposition = ""
    S.imeCursor = 0
end

function M.OpenPlayerDialog()
    input:SetScreenKeyboardVisible(true)
    S.dialogMode = "player"
    S.playerParamInputs = {
        tostring(S.playerParams.baseJumpGrids),
        tostring(S.playerParams.fallJumpMultiplier),
        tostring(S.playerParams.maxFallGrids),
        tostring(S.playerParams.maxJumpGrids),
        tostring(S.playerParams.defaultLightDiameter),
        tostring(S.playerParams.cameraZoom),
    }
    S.playerParamFocus = 1
    S.playerParamCursor = #S.playerParamInputs[1]
    S.renameBlink = 0
    S.imeComposition = ""
    S.imeCursor = 0
end

function M.OpenLightDialog(lightIdx)
    input:SetScreenKeyboardVisible(true)
    S.selectedLightIndex = lightIdx
    local light = FogOfWar.GetLight(lightIdx)
    -- 熄灭灯 diameter=0，对话框显示 targetDiameter（点亮后的范围）
    local displayDiameter = light.extinguished and (light.targetDiameter or 6) or light.diameter
    S.lightDiameterInput = tostring(displayDiameter)
    S.lightFeatherInput = tostring(light.feather)
    S.lightGroupInput = tostring(light.group or 0)
    S.dialogMode = "light"
    S.lightDialogFocus = 1
    S.lightDialogCursor = #S.lightDiameterInput
    S.renameBlink = 0
    S.imeComposition = ""
    S.imeCursor = 0
end

function M.OpenRenameDialog(lv)
    input:SetScreenKeyboardVisible(true)
    S.dialogMode = "rename"
    S.dialogTarget = lv
    S.renameInput = lv.name
    S.renameCursor = #lv.name
    S.renameBlink = 0
    S.imeComposition = ""
    S.imeCursor = 0
    -- 使用 UI Modal 对话框（用户点击 TextField 触发 IME，支持剪贴板）
    CreateRenameUI(lv.name)
end

function M.OpenDeleteDialog(lv)
    input:SetScreenKeyboardVisible(true)
    S.dialogMode = "delete"
    S.dialogTarget = lv
end

function M.OpenTrashDialog()
    S.dialogMode = "trash"
    S.trashDialogList = CloudStorage.ListTrash()
    S.trashDialogScroll = 0
end

-- 可选的背景图列表（资源路径，相对于 assets/）
local BG_IMAGE_OPTIONS = {
    { path = "image/传火祭祀场背景_20260530100114.png", name = "传火祭祀场(火光)" },
    { path = "image/edited_传火祭祀场背景_无火光_20260530100627.png", name = "传火祭祀场(无火光)" },
    { path = "image/sewer_background_20260530144651.png", name = "下水道背景" },
}

function M.OpenBackgroundDialog()
    input:SetScreenKeyboardVisible(true)
    S.dialogMode = "background"
    -- 找到当前选中项索引
    S.bgDialogSelected = 0
    for i, opt in ipairs(BG_IMAGE_OPTIONS) do
        if opt.path == S.backgroundImage then
            S.bgDialogSelected = i
            break
        end
    end
    -- 初始化明暗度输入
    S.bgAlphaInput = tostring(math.floor(S.bgImageAlpha * 100 + 0.5))
    S.bgAlphaCursor = #S.bgAlphaInput
    S.renameBlink = 0
end

function M.OpenDecorationDialog()
    S.dialogMode = "decoration"
    S.decoDialogBrightnessInput = tostring(S.decoDialogBrightness)
    S.decoDialogScaleInput = tostring(S.decoDialogScale)
    S.decoDialogFocusField = 0  -- 不自动聚焦，让用户看到当前值后点击编辑
    S.decoDialogCursor = 0
    S.renameBlink = 0
end

-- ====================================================================
-- 确认逻辑
-- ====================================================================

function M.ApplyPlayerParams()
    local p = S.playerParams
    p.baseJumpGrids = tonumber(S.playerParamInputs[1]) or p.baseJumpGrids
    p.fallJumpMultiplier = tonumber(S.playerParamInputs[2]) or p.fallJumpMultiplier
    p.maxFallGrids = tonumber(S.playerParamInputs[3]) or p.maxFallGrids
    p.maxJumpGrids = tonumber(S.playerParamInputs[4]) or p.maxJumpGrids
    p.defaultLightDiameter = tonumber(S.playerParamInputs[5]) or p.defaultLightDiameter
    p.cameraZoom = tonumber(S.playerParamInputs[6]) or p.cameraZoom

    -- 保存全局玩家参数到本地文件
    CloudStorage.SavePlayerParams({
        baseJumpGrids = p.baseJumpGrids,
        fallJumpMultiplier = p.fallJumpMultiplier,
        maxFallGrids = p.maxFallGrids,
        maxJumpGrids = p.maxJumpGrids,
        defaultLightDiameter = p.defaultLightDiameter,
        cameraZoom = p.cameraZoom,
    }, function(ok, err)
        if ok then
            S.SetMessage("玩家参数已保存", 1.5)
        else
            S.SetMessage("玩家参数保存失败: " .. (err or "未知"), 2.5)
        end
    end)
end

function M.ConfirmDialog()
    if S.dialogMode == "rename" and S.dialogTarget then
        -- 从 TextField 获取最新值
        if renameTextField_ then
            S.renameInput = renameTextField_:GetValue() or S.renameInput
        end
        if S.renameInput ~= "" then
            Persistence.RenameLevel(S.dialogTarget.file, S.renameInput)
        end
        DestroyRenameUI()
    elseif S.dialogMode == "delete" and S.dialogTarget then
        Persistence.DeleteLevel(S.dialogTarget.file)
    elseif S.dialogMode == "canvas" then
        local newW = tonumber(S.canvasWidthInput) or S.MAP_COLS
        local newH = tonumber(S.canvasHeightInput) or S.MAP_ROWS
        MapData.ResizeCanvas(newW, newH)
    elseif S.dialogMode == "player" then
        M.ApplyPlayerParams()
    elseif S.dialogMode == "light" then
        if S.selectedLightIndex > 0 then
            local d = tonumber(S.lightDiameterInput) or 6
            local f = tonumber(S.lightFeatherInput) or 0.5
            local g = tonumber(S.lightGroupInput) or 0
            FogOfWar.UpdateLight(S.selectedLightIndex, d, f, g)
        end
    elseif S.dialogMode == "background" then
        local sel = S.bgDialogSelected
        if sel >= 1 and sel <= #BG_IMAGE_OPTIONS then
            local newPath = BG_IMAGE_OPTIONS[sel].path
            if newPath ~= S.backgroundImage then
                S.backgroundImage = newPath
                S.bgImageHandle = nil  -- 清除缓存，触发重新加载
            end
            S.SetMessage("背景已设置", 1.5)
        else
            -- sel == 0 表示"无背景"
            S.backgroundImage = ""
            S.bgImageHandle = nil
            S.SetMessage("背景已清除", 1.5)
        end
        -- 应用明暗度
        local val = tonumber(S.bgAlphaInput)
        if val then
            S.bgImageAlpha = math.max(0, math.min(100, val)) / 100
        end
    elseif S.dialogMode == "decoration" then
        local typeId = S.currentDecorationType
        -- 从输入框文本解析数值
        local bVal = tonumber(S.decoDialogBrightnessInput) or 100
        local brightness = math.max(0, math.min(100, math.floor(bVal)))
        local sVal = tonumber(S.decoDialogScaleInput) or 100
        local scale = math.max(10, math.min(1000, math.floor(sVal)))
        S.decoDialogBrightness = brightness
        S.decoDialogScale = scale
        local Undo = require "editor.UndoSystem"
        if S.decoDialogEditIndex > 0 and S.decoDialogEditIndex <= #S.decorations then
            -- 编辑已有装饰
            local deco = S.decorations[S.decoDialogEditIndex]
            deco.typeId = typeId
            deco.brightness = brightness
            deco.scale = scale
        else
            -- 新建装饰
            table.insert(S.decorations, {
                col = S.decoDialogCol,
                row = S.decoDialogRow,
                typeId = typeId,
                brightness = brightness,
                scale = scale,
            })
        end
        Undo.dirty = true
        Undo.saveTimer = Undo.saveDelay
        S.SetMessage("装饰已放置", 1.5)
    end
    S.dialogMode = nil
    S.dialogTarget = nil
    S.imeComposition = ""
    S.imeCursor = 0
    input:SetScreenKeyboardVisible(false)
end

function M.CancelDialog()
    if S.dialogMode == "rename" then
        DestroyRenameUI()
    end
    S.dialogMode = nil
    S.dialogTarget = nil
    S.imeComposition = ""
    S.imeCursor = 0
    input:SetScreenKeyboardVisible(false)
end

-- ====================================================================
-- 对话框尺寸计算
-- ====================================================================

local function GetDialogSize()
    local w, h = 180, 65
    if S.dialogMode == "rename" then h = 80
    elseif S.dialogMode == "canvas" then h = 100
    elseif S.dialogMode == "player" then w = 200; h = 190
    elseif S.dialogMode == "light" then h = 122
    elseif S.dialogMode == "background" then w = 200; h = 30 + (#BG_IMAGE_OPTIONS + 1) * 18 + 24 + 20 + 32
    elseif S.dialogMode == "decoration" then
        local typeCount = #C.DECORATION_TYPES
        local rows = math.ceil(typeCount / 3)
        w = 210; h = 30 + rows * 22 + 60 + 36  -- title + type grid + sliders + buttons
    elseif S.dialogMode == "trash" then
        local itemCount = S.trashDialogList and #S.trashDialogList or 0
        local visibleItems = math.min(itemCount, 6)
        w = 220; h = 30 + math.max(visibleItems, 1) * 20 + 36
    end
    return w, h
end

local function GetDialogRect()
    local w, h = GetDialogSize()
    local x = (S.screenDesignW - w) * 0.5
    local y = (S.screenDesignH - h) * 0.5
    return x, y, w, h
end

-- ====================================================================
-- 渲染辅助
-- ====================================================================

local function DrawDialogFrame(vg, dlgX, dlgY, dlgW, dlgH)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, 6)
    nvgFillColor(vg, nvgRGBA(30, 30, 45, 250))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, 6)
    nvgStrokeColor(vg, nvgRGBA(100, 110, 140, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

local function DrawTitle(vg, dlgX, dlgW, dlgY, text, r, g, b)
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(r, g, b, 255))
    nvgText(vg, dlgX + dlgW * 0.5, dlgY + 14, text)
end

local function DrawButtons(vg, dlgX, dlgY, dlgW, dlgH, confirmLabel, confirmR, confirmG, confirmB)
    local btnW2 = 50
    local btnH2 = 16
    local btnY3 = dlgY + dlgH - btnH2 - 10
    local confirmX = dlgX + dlgW * 0.5 - btnW2 - 6
    local cancelX = dlgX + dlgW * 0.5 + 6

    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnY3, btnW2, btnH2, 3)
    nvgFillColor(vg, nvgRGBA(confirmR, confirmG, confirmB, 255))
    nvgFill(vg)
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 255, 240, 255))
    nvgText(vg, confirmX + btnW2 * 0.5, btnY3 + btnH2 * 0.5, confirmLabel)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnY3, btnW2, btnH2, 3)
    nvgFillColor(vg, nvgRGBA(80, 70, 70, 255))
    nvgFill(vg)
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    nvgText(vg, cancelX + btnW2 * 0.5, btnY3 + btnH2 * 0.5, "取消")
end

local function DrawInputBox(vg, x, y, w, h, text, isFocused)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 3)
    nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 3)
    local bc = isFocused and nvgRGBA(80, 160, 80, 220) or nvgRGBA(60, 60, 80, 200)
    nvgStrokeColor(vg, bc)
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
    nvgText(vg, x + w * 0.5, y + h * 0.5, text)
end

local function DrawCursorCentered(vg, x, y, w, h, fullText, cursorPos, cr, cg, cb)
    if math.floor(S.renameBlink * 2) % 2 ~= 0 then return end
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local tbc = string.sub(fullText, 1, cursorPos)
    local bounds = {}
    local tw = nvgTextBounds(vg, 0, 0, tbc, bounds)
    local fullBounds = {}
    local fullW = nvgTextBounds(vg, 0, 0, fullText, fullBounds)
    local textStartX = x + (w - fullW) * 0.5
    nvgBeginPath(vg)
    nvgMoveTo(vg, textStartX + tw, y + 3)
    nvgLineTo(vg, textStartX + tw, y + h - 3)
    nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

-- ====================================================================
-- 各对话框渲染
-- ====================================================================

local function DrawRenameDialog(vg, dlgX, dlgY, dlgW, dlgH)
    DrawTitle(vg, dlgX, dlgW, dlgY, "重命名关卡", 255, 220, 100)

    -- 输入框区域由 UI TextField 覆盖层渲染，这里只绘制一个占位背景
    local inputX = dlgX + 12
    local inputY = dlgY + 26
    local inputW = dlgW - 24
    local inputH = 18

    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, 3)
    nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
    nvgFill(vg)

    DrawButtons(vg, dlgX, dlgY, dlgW, dlgH, "确认", 40, 120, 60)
end

local function DrawDeleteDialog(vg, dlgX, dlgY, dlgW, dlgH)
    DrawTitle(vg, dlgX, dlgW, dlgY, "删除关卡", 255, 100, 80)

    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
    local name = S.dialogTarget and S.dialogTarget.name or ""
    nvgText(vg, dlgX + dlgW * 0.5, dlgY + 30, "确定删除 \"" .. name .. "\" ?")

    DrawButtons(vg, dlgX, dlgY, dlgW, dlgH, "删除", 160, 40, 40)
end

local function DrawCanvasDialog(vg, dlgX, dlgY, dlgW, dlgH)
    DrawTitle(vg, dlgX, dlgW, dlgY, "画布大小", 180, 220, 100)

    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 200))
    nvgText(vg, dlgX + dlgW * 0.5, dlgY + 26, "范围: 宽10~200  高5~100")

    local inputW = 50
    local inputH = 16
    local fieldY1 = dlgY + 34
    local fieldY2 = dlgY + 56
    local wInputX = dlgX + dlgW * 0.5 - inputW * 0.5

    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
    nvgText(vg, wInputX - 6, fieldY1 + inputH * 0.5, "宽度:")
    nvgText(vg, wInputX - 6, fieldY2 + inputH * 0.5, "高度:")

    DrawInputBox(vg, wInputX, fieldY1, inputW, inputH, S.canvasWidthInput, S.canvasFocusField == 1)
    if S.canvasFocusField == 1 then
        DrawCursorCentered(vg, wInputX, fieldY1, inputW, inputH, S.canvasWidthInput, S.canvasCursor, 200, 255, 200)
    end

    DrawInputBox(vg, wInputX, fieldY2, inputW, inputH, S.canvasHeightInput, S.canvasFocusField == 2)
    if S.canvasFocusField == 2 then
        DrawCursorCentered(vg, wInputX, fieldY2, inputW, inputH, S.canvasHeightInput, S.canvasCursor, 200, 255, 200)
    end

    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 180))
    nvgText(vg, wInputX + inputW + 6, fieldY1 + inputH * 0.5, "格")
    nvgText(vg, wInputX + inputW + 6, fieldY2 + inputH * 0.5, "格")

    DrawButtons(vg, dlgX, dlgY, dlgW, dlgH, "确认", 40, 120, 60)
end

local function DrawPlayerDialog(vg, dlgX, dlgY, dlgW, dlgH)
    DrawTitle(vg, dlgX, dlgW, dlgY, "玩家参数", 255, 200, 80)

    local inputW = 50
    local inputH = 14
    local startY = dlgY + 28
    local rowGap = 20
    local inputX = dlgX + dlgW * 0.5 - inputW * 0.5

    for i = 1, #S.playerParamInputs do
        local fieldY = startY + (i - 1) * rowGap
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
        nvgText(vg, inputX - 6, fieldY + inputH * 0.5, C.PLAYER_PARAM_LABELS[i])

        local isFocused = (S.playerParamFocus == i)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, inputX, fieldY, inputW, inputH, 3)
        nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, inputX, fieldY, inputW, inputH, 3)
        local bc = isFocused and nvgRGBA(200, 160, 50, 220) or nvgRGBA(60, 60, 80, 200)
        nvgStrokeColor(vg, bc)
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
        nvgText(vg, inputX + inputW * 0.5, fieldY + inputH * 0.5, S.playerParamInputs[i])

        if isFocused then
            DrawCursorCentered(vg, inputX, fieldY, inputW, inputH, S.playerParamInputs[i], S.playerParamCursor, 255, 220, 100)
        end
    end

    DrawButtons(vg, dlgX, dlgY, dlgW, dlgH, "确认", 40, 120, 60)
end

local function DrawLightDialog(vg, dlgX, dlgY, dlgW, dlgH)
    DrawTitle(vg, dlgX, dlgW, dlgY, "光源参数", 255, 220, 80)

    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 200))
    nvgText(vg, dlgX + dlgW * 0.5, dlgY + 26, "直径:2~30格  羽化:0.0~1.0  编组:0~9")

    local inputW = 50
    local inputH = 16
    local fieldY1 = dlgY + 34
    local fieldY2 = dlgY + 56
    local fieldY3 = dlgY + 78
    local dInputX = dlgX + dlgW * 0.5 - inputW * 0.5

    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
    nvgText(vg, dInputX - 6, fieldY1 + inputH * 0.5, "直径:")
    nvgText(vg, dInputX - 6, fieldY2 + inputH * 0.5, "羽化:")
    nvgText(vg, dInputX - 6, fieldY3 + inputH * 0.5, "编组:")

    local focus1 = (S.lightDialogFocus == 1)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dInputX, fieldY1, inputW, inputH, 3)
    nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dInputX, fieldY1, inputW, inputH, 3)
    nvgStrokeColor(vg, focus1 and nvgRGBA(255, 200, 50, 220) or nvgRGBA(60, 60, 80, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
    nvgText(vg, dInputX + inputW * 0.5, fieldY1 + inputH * 0.5, S.lightDiameterInput)
    if focus1 then
        DrawCursorCentered(vg, dInputX, fieldY1, inputW, inputH, S.lightDiameterInput, S.lightDialogCursor, 255, 220, 100)
    end

    local focus2 = (S.lightDialogFocus == 2)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dInputX, fieldY2, inputW, inputH, 3)
    nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dInputX, fieldY2, inputW, inputH, 3)
    nvgStrokeColor(vg, focus2 and nvgRGBA(255, 200, 50, 220) or nvgRGBA(60, 60, 80, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
    nvgText(vg, dInputX + inputW * 0.5, fieldY2 + inputH * 0.5, S.lightFeatherInput)
    if focus2 then
        DrawCursorCentered(vg, dInputX, fieldY2, inputW, inputH, S.lightFeatherInput, S.lightDialogCursor, 255, 220, 100)
    end

    local focus3 = (S.lightDialogFocus == 3)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dInputX, fieldY3, inputW, inputH, 3)
    nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dInputX, fieldY3, inputW, inputH, 3)
    nvgStrokeColor(vg, focus3 and nvgRGBA(100, 180, 255, 220) or nvgRGBA(60, 60, 80, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
    nvgText(vg, dInputX + inputW * 0.5, fieldY3 + inputH * 0.5, S.lightGroupInput)
    if focus3 then
        DrawCursorCentered(vg, dInputX, fieldY3, inputW, inputH, S.lightGroupInput, S.lightDialogCursor, 100, 180, 255)
    end

    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 180))
    nvgText(vg, dInputX + inputW + 6, fieldY1 + inputH * 0.5, "格")

    DrawButtons(vg, dlgX, dlgY, dlgW, dlgH, "确认", 40, 120, 60)
end

local function DrawBackgroundDialog(vg, dlgX, dlgY, dlgW, dlgH)
    DrawTitle(vg, dlgX, dlgW, dlgY, "选择背景图", 120, 200, 255)

    local itemH = 18
    local startY = dlgY + 28
    local itemX = dlgX + 12
    local itemW = dlgW - 24

    -- "无背景" 选项
    local isSelected = (S.bgDialogSelected == 0)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, itemX, startY, itemW, itemH - 2, 3)
    if isSelected then
        nvgFillColor(vg, nvgRGBA(60, 80, 120, 255))
    else
        nvgFillColor(vg, nvgRGBA(25, 25, 40, 255))
    end
    nvgFill(vg)
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, isSelected and nvgRGBA(255, 255, 255, 255) or nvgRGBA(180, 180, 200, 255))
    nvgText(vg, itemX + 6, startY + itemH * 0.5 - 1, "无背景")

    -- 图片选项列表
    for i, opt in ipairs(BG_IMAGE_OPTIONS) do
        local iy = startY + i * itemH
        isSelected = (S.bgDialogSelected == i)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, itemX, iy, itemW, itemH - 2, 3)
        if isSelected then
            nvgFillColor(vg, nvgRGBA(60, 80, 120, 255))
        else
            nvgFillColor(vg, nvgRGBA(25, 25, 40, 255))
        end
        nvgFill(vg)
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, isSelected and nvgRGBA(255, 255, 255, 255) or nvgRGBA(180, 180, 200, 255))
        nvgText(vg, itemX + 6, iy + itemH * 0.5 - 1, opt.name)
    end

    -- 明暗度输入（实时预览）
    local alphaY = startY + (#BG_IMAGE_OPTIONS + 1) * itemH + 4
    local inputW = 36
    local inputH = 16
    local inputX = dlgX + dlgW * 0.5 - inputW * 0.5
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
    nvgText(vg, inputX - 6, alphaY + inputH * 0.5, "明暗度:")
    DrawInputBox(vg, inputX, alphaY, inputW, inputH, S.bgAlphaInput, true)
    DrawCursorCentered(vg, inputX, alphaY, inputW, inputH, S.bgAlphaInput, S.bgAlphaCursor or 0, 120, 200, 255)
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 180))
    nvgText(vg, inputX + inputW + 6, alphaY + inputH * 0.5, "%")

    -- 拉伸选项 checkbox
    local checkY = alphaY + inputH + 6
    local checkSize = 10
    local checkX = itemX + 6
    nvgBeginPath(vg)
    nvgRoundedRect(vg, checkX, checkY + 2, checkSize, checkSize, 2)
    nvgStrokeColor(vg, nvgRGBA(120, 140, 180, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    if S.bgStretchToCanvas then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, checkX + 2, checkY + 4, checkSize - 4, checkSize - 4, 1)
        nvgFillColor(vg, nvgRGBA(100, 180, 255, 255))
        nvgFill(vg)
    end
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
    nvgText(vg, checkX + checkSize + 6, checkY + checkSize * 0.5 + 2, "拉伸为画布大小")

    DrawButtons(vg, dlgX, dlgY, dlgW, dlgH, "确认", 40, 100, 140)
end

-- ====================================================================
-- 装饰物配置弹窗
-- ====================================================================

local function DrawDecorationDialog(vg, dlgX, dlgY, dlgW, dlgH)
    local isEdit = S.decoDialogEditIndex > 0
    local title = isEdit and "编辑装饰物" or "放置装饰物"
    DrawTitle(vg, dlgX, dlgW, dlgY, title, 180, 160, 220)

    local types = C.DECORATION_TYPES
    local cols = 3
    local itemW = math.floor((dlgW - 24) / cols)
    local itemH = 20
    local startX = dlgX + 12
    local startY = dlgY + 28

    -- 类型选择网格
    for i, dt in ipairs(types) do
        local r = math.ceil(i / cols)
        local c = ((i - 1) % cols) + 1
        local ix = startX + (c - 1) * itemW
        local iy = startY + (r - 1) * itemH

        local selected = (S.currentDecorationType == i)
        -- 选中高亮背景
        if selected then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix, iy, itemW - 2, itemH - 2, 3)
            nvgFillColor(vg, nvgRGBA(80, 90, 140, 200))
            nvgFill(vg)
        end

        -- 颜色指示点
        local clr = dt.color or {180, 140, 220}
        nvgBeginPath(vg)
        nvgCircle(vg, ix + 6, iy + itemH * 0.5 - 1, 4)
        nvgFillColor(vg, nvgRGBA(clr[1], clr[2], clr[3], 255))
        nvgFill(vg)

        -- 名称
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
        nvgText(vg, ix + 14, iy + itemH * 0.5 - 1, dt.name)
    end

    -- 输入框区域
    local typeRows = math.ceil(#types / cols)
    local fieldStartY = startY + typeRows * itemH + 8
    local inputW = 50
    local inputH = 16
    local gap = 22
    local inputX = dlgX + dlgW * 0.5 - inputW * 0.5

    -- 明暗度输入框
    local fieldY1 = fieldStartY
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 255))
    nvgText(vg, inputX - 6, fieldY1 + inputH * 0.5, "明暗:")

    local bText = S.decoDialogBrightnessInput
    if #bText == 0 and S.decoDialogFocusField ~= 1 then bText = tostring(S.decoDialogBrightness) end
    DrawInputBox(vg, inputX, fieldY1, inputW, inputH, bText, S.decoDialogFocusField == 1)
    if S.decoDialogFocusField == 1 then
        DrawCursorCentered(vg, inputX, fieldY1, inputW, inputH, S.decoDialogBrightnessInput, S.decoDialogCursor, 120, 140, 200)
    end

    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 180))
    nvgText(vg, inputX + inputW + 6, fieldY1 + inputH * 0.5, "% (0~100)")

    -- 缩放输入框
    local fieldY2 = fieldStartY + gap
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 255))
    nvgText(vg, inputX - 6, fieldY2 + inputH * 0.5, "缩放:")

    local sText = S.decoDialogScaleInput
    if #sText == 0 and S.decoDialogFocusField ~= 2 then sText = tostring(S.decoDialogScale) end
    DrawInputBox(vg, inputX, fieldY2, inputW, inputH, sText, S.decoDialogFocusField == 2)
    if S.decoDialogFocusField == 2 then
        DrawCursorCentered(vg, inputX, fieldY2, inputW, inputH, S.decoDialogScaleInput, S.decoDialogCursor, 140, 180, 120)
    end

    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 180))
    nvgText(vg, inputX + inputW + 6, fieldY2 + inputH * 0.5, "% (10~1000)")

    DrawButtons(vg, dlgX, dlgY, dlgW, dlgH, "确认", 60, 100, 160)
end

local function DrawTrashDialog(vg, dlgX, dlgY, dlgW, dlgH)
    DrawTitle(vg, dlgX, dlgW, dlgY, "回收站", 255, 140, 120)

    local list = S.trashDialogList or {}
    local itemH = 20
    local startY = dlgY + 26
    local itemX = dlgX + 8
    local itemW = dlgW - 16
    local restoreBtnW = 28
    local restoreBtnH = 12

    -- 存储按钮区域供点击使用
    S.trashDialogBtns = {}

    if #list == 0 then
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 140, 160, 200))
        nvgText(vg, dlgX + dlgW * 0.5, startY + 20, "回收站为空")
    else
        local visibleCount = math.min(#list, 6)
        for i = 1, visibleCount do
            local item = list[i]
            local iy = startY + (i - 1) * itemH

            -- 行背景（交替色）
            nvgBeginPath(vg)
            nvgRoundedRect(vg, itemX, iy, itemW, itemH - 2, 3)
            if i % 2 == 0 then
                nvgFillColor(vg, nvgRGBA(30, 28, 40, 255))
            else
                nvgFillColor(vg, nvgRGBA(25, 25, 35, 255))
            end
            nvgFill(vg)

            -- 文件名
            nvgFontSize(vg, 8)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
            local displayName = item.fname:gsub("%.json$", "")
            nvgText(vg, itemX + 4, iy + itemH * 0.5 - 1, displayName)

            -- 剩余时间
            local hours = math.floor(item.remainSeconds / 3600)
            local mins = math.floor((item.remainSeconds % 3600) / 60)
            local timeStr = hours .. "h" .. mins .. "m"
            nvgFontSize(vg, 7)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(120, 120, 140, 180))
            nvgText(vg, itemX + itemW - restoreBtnW - 6, iy + itemH * 0.5 - 1, timeStr)

            -- 还原按钮
            local btnX = itemX + itemW - restoreBtnW - 2
            local btnY = iy + (itemH - restoreBtnH) * 0.5 - 1
            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, restoreBtnW, restoreBtnH, 2)
            nvgFillColor(vg, nvgRGBA(40, 120, 80, 255))
            nvgFill(vg)
            nvgFontSize(vg, 7)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(230, 255, 230, 255))
            nvgText(vg, btnX + restoreBtnW * 0.5, btnY + restoreBtnH * 0.5, "还原")

            -- 记录按钮区域
            S.trashDialogBtns[i] = { x = btnX, y = btnY, w = restoreBtnW, h = restoreBtnH, fname = item.fname }
        end
    end

    -- 底部关闭按钮
    local closeBtnW = 50
    local closeBtnH = 16
    local closeBtnX = dlgX + (dlgW - closeBtnW) * 0.5
    local closeBtnY = dlgY + dlgH - closeBtnH - 8
    nvgBeginPath(vg)
    nvgRoundedRect(vg, closeBtnX, closeBtnY, closeBtnW, closeBtnH, 3)
    nvgFillColor(vg, nvgRGBA(60, 55, 65, 255))
    nvgFill(vg)
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    nvgText(vg, closeBtnX + closeBtnW * 0.5, closeBtnY + closeBtnH * 0.5, "关闭")

    S.trashDialogCloseBtn = { x = closeBtnX, y = closeBtnY, w = closeBtnW, h = closeBtnH }
end

-- ====================================================================
-- 主渲染入口
-- ====================================================================

function M.Draw()
    if not S.dialogMode then return end

    -- rename 模式由 UI.Modal 独立渲染，不绘制 NanoVG 对话框
    if S.dialogMode == "rename" then return end

    local vg = S.vg

    -- 遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, S.screenDesignW, S.screenDesignH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    local dlgX, dlgY, dlgW, dlgH = GetDialogRect()
    DrawDialogFrame(vg, dlgX, dlgY, dlgW, dlgH)
    nvgFontFace(vg, "sans")

    if S.dialogMode == "delete" then
        DrawDeleteDialog(vg, dlgX, dlgY, dlgW, dlgH)
    elseif S.dialogMode == "canvas" then
        DrawCanvasDialog(vg, dlgX, dlgY, dlgW, dlgH)
    elseif S.dialogMode == "player" then
        DrawPlayerDialog(vg, dlgX, dlgY, dlgW, dlgH)
    elseif S.dialogMode == "light" then
        DrawLightDialog(vg, dlgX, dlgY, dlgW, dlgH)
    elseif S.dialogMode == "background" then
        DrawBackgroundDialog(vg, dlgX, dlgY, dlgW, dlgH)
    elseif S.dialogMode == "decoration" then
        DrawDecorationDialog(vg, dlgX, dlgY, dlgW, dlgH)
    elseif S.dialogMode == "trash" then
        DrawTrashDialog(vg, dlgX, dlgY, dlgW, dlgH)
    end
end

-- ====================================================================
-- 键盘输入处理
-- ====================================================================

local function HandleRenameKey(key)
    -- IME 正在组合时，不拦截编辑键（让 IME 自行处理）
    if S.imeComposition and #S.imeComposition > 0 then
        return
    end

    -- Ctrl+V 粘贴
    if key == KEY_V and input:GetKeyDown(KEY_CTRL) then
        local clipText = ui:GetClipboardText()
        if clipText and #clipText > 0 then
            -- 移除换行符
            clipText = clipText:gsub("[\r\n]+", "")
            if #S.renameInput + #clipText <= 60 then
                S.renameInput = string.sub(S.renameInput, 1, S.renameCursor) .. clipText .. string.sub(S.renameInput, S.renameCursor + 1)
                S.renameCursor = S.renameCursor + #clipText
                S.renameBlink = 0
            end
        end
        return
    end
    -- Ctrl+A 全选（选中所有文本，光标移到末尾）
    if key == KEY_A and input:GetKeyDown(KEY_CTRL) then
        S.renameCursor = #S.renameInput
        S.renameBlink = 0
        return
    end
    if key == KEY_BACKSPACE then
        if S.renameCursor > 0 then
            local pos = S.renameCursor
            while pos > 0 do
                pos = pos - 1
                local byte = string.byte(S.renameInput, pos + 1) or 0
                if byte < 0x80 or byte >= 0xC0 then break end
            end
            S.renameInput = string.sub(S.renameInput, 1, pos) .. string.sub(S.renameInput, S.renameCursor + 1)
            S.renameCursor = pos
            S.renameBlink = 0
        end
    elseif key == KEY_DELETE then
        if S.renameCursor < #S.renameInput then
            local pos = S.renameCursor + 1
            while pos < #S.renameInput do
                local nb = string.byte(S.renameInput, pos + 1) or 0
                if nb < 0x80 or nb >= 0xC0 then break end
                pos = pos + 1
            end
            S.renameInput = string.sub(S.renameInput, 1, S.renameCursor) .. string.sub(S.renameInput, pos + 1)
            S.renameBlink = 0
        end
    elseif key == KEY_LEFT then
        if S.renameCursor > 0 then
            local pos = S.renameCursor - 1
            while pos > 0 do
                local byte = string.byte(S.renameInput, pos + 1) or 0
                if byte < 0x80 or byte >= 0xC0 then break end
                pos = pos - 1
            end
            S.renameCursor = pos
            S.renameBlink = 0
        end
    elseif key == KEY_RIGHT then
        if S.renameCursor < #S.renameInput then
            local pos = S.renameCursor + 1
            while pos < #S.renameInput do
                local nb = string.byte(S.renameInput, pos + 1) or 0
                if nb < 0x80 or nb >= 0xC0 then break end
                pos = pos + 1
            end
            S.renameCursor = pos
            S.renameBlink = 0
        end
    elseif key == KEY_HOME then
        S.renameCursor = 0; S.renameBlink = 0
    elseif key == KEY_END then
        S.renameCursor = #S.renameInput; S.renameBlink = 0
    end
end

local function HandleNumericFieldKey(key, currentInput, cursor)
    if key == KEY_BACKSPACE then
        if cursor > 0 then
            currentInput = string.sub(currentInput, 1, cursor - 1) .. string.sub(currentInput, cursor + 1)
            cursor = cursor - 1
        end
    elseif key == KEY_DELETE then
        if cursor < #currentInput then
            currentInput = string.sub(currentInput, 1, cursor) .. string.sub(currentInput, cursor + 2)
        end
    elseif key == KEY_LEFT then
        cursor = math.max(0, cursor - 1)
    elseif key == KEY_RIGHT then
        cursor = math.min(#currentInput, cursor + 1)
    elseif key == KEY_HOME then
        cursor = 0
    elseif key == KEY_END then
        cursor = #currentInput
    end
    S.renameBlink = 0
    return currentInput, cursor
end

function M.HandleKeyDown(key)
    if not S.dialogMode then return false end

    if key == KEY_ESCAPE then
        S.imeComposition = ""
        S.imeCursor = 0
        M.CancelDialog()
        return true
    end

    -- rename 模式下，键盘输入完全交给 UI TextField 处理（除了 ESC）
    if S.dialogMode == "rename" then
        -- 不拦截任何键，让 UI 库的 AutoEvents 处理
        return false
    end

    if key == KEY_RETURN or key == KEY_KP_ENTER then
        M.ConfirmDialog()
        return true
    end

    -- background 模式：处理明暗度输入框的键盘
    if S.dialogMode == "background" then
        S.bgAlphaInput, S.bgAlphaCursor = HandleNumericFieldKey(key, S.bgAlphaInput, S.bgAlphaCursor or 0)
        -- 实时应用明暗度预览
        local val = tonumber(S.bgAlphaInput)
        if val then
            S.bgImageAlpha = math.max(0, math.min(100, val)) / 100
        end
        return true
    end

    if key == KEY_TAB then
        if S.dialogMode == "light" then
            if S.lightDialogFocus == 1 then
                S.lightDialogFocus = 2
                S.lightDialogCursor = #S.lightFeatherInput
            elseif S.lightDialogFocus == 2 then
                S.lightDialogFocus = 3
                S.lightDialogCursor = #S.lightGroupInput
            else
                S.lightDialogFocus = 1
                S.lightDialogCursor = #S.lightDiameterInput
            end
            S.renameBlink = 0
        elseif S.dialogMode == "player" then
            S.playerParamFocus = (S.playerParamFocus % #S.playerParamInputs) + 1
            S.playerParamCursor = #S.playerParamInputs[S.playerParamFocus]
            S.renameBlink = 0
        elseif S.dialogMode == "canvas" then
            if S.canvasFocusField == 1 then
                S.canvasFocusField = 2
                S.canvasCursor = #S.canvasHeightInput
            else
                S.canvasFocusField = 1
                S.canvasCursor = #S.canvasWidthInput
            end
            S.renameBlink = 0
        elseif S.dialogMode == "decoration" then
            if S.decoDialogFocusField == 1 then
                S.decoDialogFocusField = 2
                S.decoDialogScaleInput = ""
                S.decoDialogCursor = 0
            else
                S.decoDialogFocusField = 1
                S.decoDialogBrightnessInput = ""
                S.decoDialogCursor = 0
            end
            S.renameBlink = 0
        end
        return true
    end

    if S.dialogMode == "canvas" then
        local cur = (S.canvasFocusField == 1) and S.canvasWidthInput or S.canvasHeightInput
        cur, S.canvasCursor = HandleNumericFieldKey(key, cur, S.canvasCursor)
        if S.canvasFocusField == 1 then S.canvasWidthInput = cur else S.canvasHeightInput = cur end
    elseif S.dialogMode == "player" then
        local cur = S.playerParamInputs[S.playerParamFocus]
        cur, S.playerParamCursor = HandleNumericFieldKey(key, cur, S.playerParamCursor)
        S.playerParamInputs[S.playerParamFocus] = cur
    elseif S.dialogMode == "light" then
        local cur
        if S.lightDialogFocus == 1 then cur = S.lightDiameterInput
        elseif S.lightDialogFocus == 2 then cur = S.lightFeatherInput
        else cur = S.lightGroupInput end
        cur, S.lightDialogCursor = HandleNumericFieldKey(key, cur, S.lightDialogCursor)
        if S.lightDialogFocus == 1 then S.lightDiameterInput = cur
        elseif S.lightDialogFocus == 2 then S.lightFeatherInput = cur
        else S.lightGroupInput = cur end
    elseif S.dialogMode == "decoration" and S.decoDialogFocusField > 0 then
        local cur = (S.decoDialogFocusField == 1) and S.decoDialogBrightnessInput or S.decoDialogScaleInput
        cur, S.decoDialogCursor = HandleNumericFieldKey(key, cur, S.decoDialogCursor)
        if S.decoDialogFocusField == 1 then S.decoDialogBrightnessInput = cur else S.decoDialogScaleInput = cur end
    end

    return true
end

-- ====================================================================
-- IME 组合输入处理（TextEditing 事件）
-- ====================================================================

function M.HandleTextEditing(composition, cursor, selectionLength)
    if not S.dialogMode then return false end
    -- 更新 IME 组合状态（拼音预览文本）
    S.imeComposition = composition or ""
    S.imeCursor = cursor or 0
    S.renameBlink = 0
    return true
end

-- ====================================================================
-- 文本输入处理
-- ====================================================================

function M.HandleTextInput(text)
    if not S.dialogMode then return false end
    if not text or #text == 0 then return true end

    -- rename 模式下，文本输入完全交给 UI TextField 处理
    if S.dialogMode == "rename" then
        return false
    end

    -- 文本确认时清除 IME 组合状态
    S.imeComposition = ""
    S.imeCursor = 0

    if S.dialogMode == "canvas" then
        local digits = text:match("%d+")
        if digits then
            local cur = (S.canvasFocusField == 1) and S.canvasWidthInput or S.canvasHeightInput
            if #cur < 4 then
                cur = string.sub(cur, 1, S.canvasCursor) .. digits .. string.sub(cur, S.canvasCursor + 1)
                S.canvasCursor = S.canvasCursor + #digits
                S.renameBlink = 0
                if S.canvasFocusField == 1 then S.canvasWidthInput = cur else S.canvasHeightInput = cur end
            end
        end
    elseif S.dialogMode == "player" then
        local valid = text:match("[%d%.]+")
        if valid then
            local cur = S.playerParamInputs[S.playerParamFocus]
            if #cur < 6 then
                cur = string.sub(cur, 1, S.playerParamCursor) .. valid .. string.sub(cur, S.playerParamCursor + 1)
                S.playerParamCursor = S.playerParamCursor + #valid
                S.renameBlink = 0
                S.playerParamInputs[S.playerParamFocus] = cur
            end
        end
    elseif S.dialogMode == "light" then
        local valid = text:match("[%d%.]+")
        if valid then
            local cur
            if S.lightDialogFocus == 1 then cur = S.lightDiameterInput
            elseif S.lightDialogFocus == 2 then cur = S.lightFeatherInput
            else cur = S.lightGroupInput end
            local maxLen = (S.lightDialogFocus == 3) and 2 or 5
            if #cur < maxLen then
                cur = string.sub(cur, 1, S.lightDialogCursor) .. valid .. string.sub(cur, S.lightDialogCursor + 1)
                S.lightDialogCursor = S.lightDialogCursor + #valid
                S.renameBlink = 0
                if S.lightDialogFocus == 1 then S.lightDiameterInput = cur
                elseif S.lightDialogFocus == 2 then S.lightFeatherInput = cur
                else S.lightGroupInput = cur end
            end
        end
    elseif S.dialogMode == "background" then
        local digits = text:match("%d+")
        if digits then
            local cur = S.bgAlphaInput
            if #cur < 3 then
                cur = string.sub(cur, 1, S.bgAlphaCursor or 0) .. digits .. string.sub(cur, (S.bgAlphaCursor or 0) + 1)
                S.bgAlphaCursor = (S.bgAlphaCursor or 0) + #digits
                S.renameBlink = 0
                S.bgAlphaInput = cur
                -- 实时应用明暗度预览
                local val = tonumber(cur)
                if val then
                    S.bgImageAlpha = math.max(0, math.min(100, val)) / 100
                end
            end
        end
    elseif S.dialogMode == "decoration" and S.decoDialogFocusField > 0 then
        local digits = text:match("%d+")
        if digits then
            local cur = (S.decoDialogFocusField == 1) and S.decoDialogBrightnessInput or S.decoDialogScaleInput
            local maxLen = (S.decoDialogFocusField == 1) and 3 or 4  -- 明暗度最多3位(100)，缩放最多4位(1000)
            if #cur < maxLen then
                cur = string.sub(cur, 1, S.decoDialogCursor) .. digits .. string.sub(cur, S.decoDialogCursor + 1)
                S.decoDialogCursor = S.decoDialogCursor + #digits
                S.renameBlink = 0
                if S.decoDialogFocusField == 1 then S.decoDialogBrightnessInput = cur else S.decoDialogScaleInput = cur end
            end
        end
    end

    return true
end

-- ====================================================================
-- 鼠标点击处理
-- ====================================================================

function M.HandleMouseDown(mx, my)
    if not S.dialogMode then return false end

    -- rename 模式由 UI.Modal 处理所有交互，仅阻止编辑器操作
    if S.dialogMode == "rename" then return true end

    local dlgX, dlgY, dlgW, dlgH = GetDialogRect()
    local btnW2 = 50
    local btnH2 = 16
    local btnY3 = dlgY + dlgH - btnH2 - 10
    local confirmX = dlgX + dlgW * 0.5 - btnW2 - 6
    local cancelX = dlgX + dlgW * 0.5 + 6

    -- 确认
    if mx >= confirmX and mx < confirmX + btnW2 and my >= btnY3 and my < btnY3 + btnH2 then
        M.ConfirmDialog()
        return true
    end
    -- 取消
    if mx >= cancelX and mx < cancelX + btnW2 and my >= btnY3 and my < btnY3 + btnH2 then
        M.CancelDialog()
        return true
    end

    -- 输入框焦点切换
    if S.dialogMode == "canvas" then
        local inputW = 50
        local inputH = 16
        local fieldY1 = dlgY + 34
        local fieldY2 = dlgY + 56
        local wInputX = dlgX + dlgW * 0.5 - inputW * 0.5
        if mx >= wInputX and mx < wInputX + inputW then
            if my >= fieldY1 and my < fieldY1 + inputH then
                S.canvasFocusField = 1; S.canvasCursor = #S.canvasWidthInput; S.renameBlink = 0
                return true
            end
            if my >= fieldY2 and my < fieldY2 + inputH then
                S.canvasFocusField = 2; S.canvasCursor = #S.canvasHeightInput; S.renameBlink = 0
                return true
            end
        end
    elseif S.dialogMode == "light" then
        local inputW = 50
        local inputH = 16
        local fieldY1 = dlgY + 34
        local fieldY2 = dlgY + 56
        local fieldY3 = dlgY + 78
        local dInputX = dlgX + dlgW * 0.5 - inputW * 0.5
        if mx >= dInputX and mx < dInputX + inputW then
            if my >= fieldY1 and my < fieldY1 + inputH then
                S.lightDialogFocus = 1; S.lightDialogCursor = #S.lightDiameterInput; S.renameBlink = 0
                return true
            end
            if my >= fieldY2 and my < fieldY2 + inputH then
                S.lightDialogFocus = 2; S.lightDialogCursor = #S.lightFeatherInput; S.renameBlink = 0
                return true
            end
            if my >= fieldY3 and my < fieldY3 + inputH then
                S.lightDialogFocus = 3; S.lightDialogCursor = #S.lightGroupInput; S.renameBlink = 0
                return true
            end
        end
    elseif S.dialogMode == "player" then
        local inputW = 50
        local inputH = 14
        local startY = dlgY + 28
        local rowGap = 20
        local inputX = dlgX + dlgW * 0.5 - inputW * 0.5
        for i = 1, #S.playerParamInputs do
            local fieldY = startY + (i - 1) * rowGap
            if mx >= inputX and mx < inputX + inputW and my >= fieldY and my < fieldY + inputH then
                S.playerParamFocus = i; S.playerParamCursor = #S.playerParamInputs[i]; S.renameBlink = 0
                return true
            end
        end
    end

    -- 背景对话框：点击列表项选中
    if S.dialogMode == "background" then
        local itemH = 18
        local startY = dlgY + 28
        local itemX = dlgX + 12
        local itemW = dlgW - 24
        -- "无背景" 选项 (index 0)
        if mx >= itemX and mx < itemX + itemW and my >= startY and my < startY + itemH - 2 then
            S.bgDialogSelected = 0
            return true
        end
        -- 图片选项
        for i = 1, #BG_IMAGE_OPTIONS do
            local iy = startY + i * itemH
            if mx >= itemX and mx < itemX + itemW and my >= iy and my < iy + itemH - 2 then
                S.bgDialogSelected = i
                return true
            end
        end
        -- 拉伸选项 checkbox 点击
        local alphaY = startY + (#BG_IMAGE_OPTIONS + 1) * itemH + 4
        local inputH = 16
        local checkY = alphaY + inputH + 6
        local checkSize = 10
        local checkX = itemX + 6
        local checkClickW = checkSize + 80  -- checkbox + 文字区域
        if mx >= checkX and mx < checkX + checkClickW and my >= checkY and my < checkY + checkSize + 4 then
            S.bgStretchToCanvas = not S.bgStretchToCanvas
            return true
        end
    end

    -- 装饰物对话框：类型选择 + 滑条拖拽
    if S.dialogMode == "decoration" then
        local types = C.DECORATION_TYPES
        local cols = 3
        local itemW = math.floor((dlgW - 24) / cols)
        local itemH = 20
        local startX = dlgX + 12
        local startY = dlgY + 28

        -- 点击类型选择
        for i = 1, #types do
            local r = math.ceil(i / cols)
            local c = ((i - 1) % cols) + 1
            local ix = startX + (c - 1) * itemW
            local iy = startY + (r - 1) * itemH
            if mx >= ix and mx < ix + itemW - 2 and my >= iy and my < iy + itemH - 2 then
                S.currentDecorationType = i
                return true
            end
        end

        -- 输入框区域
        local typeRows = math.ceil(#types / cols)
        local fieldStartY = startY + typeRows * itemH + 8
        local inputW = 50
        local inputH = 16
        local gap = 22
        local inputX = dlgX + dlgW * 0.5 - inputW * 0.5
        local fieldY1 = fieldStartY
        local fieldY2 = fieldStartY + gap

        -- 点击明暗度输入框
        if mx >= inputX and mx < inputX + inputW and my >= fieldY1 and my < fieldY1 + inputH then
            S.decoDialogFocusField = 1
            S.decoDialogBrightnessInput = ""  -- 清空以便重新输入
            S.decoDialogCursor = 0
            S.renameBlink = 0
            return true
        end

        -- 点击缩放输入框
        if mx >= inputX and mx < inputX + inputW and my >= fieldY2 and my < fieldY2 + inputH then
            S.decoDialogFocusField = 2
            S.decoDialogScaleInput = ""  -- 清空以便重新输入
            S.decoDialogCursor = 0
            S.renameBlink = 0
            return true
        end
    end

    -- 回收站对话框：还原按钮 + 关闭按钮
    if S.dialogMode == "trash" then
        -- 检查还原按钮
        if S.trashDialogBtns then
            for _, btn in ipairs(S.trashDialogBtns) do
                if mx >= btn.x and mx < btn.x + btn.w and my >= btn.y and my < btn.y + btn.h then
                    -- 执行还原
                    Persistence.RestoreLevel(btn.fname)
                    -- 刷新列表
                    S.trashDialogList = CloudStorage.ListTrash()
                    -- 如果回收站空了，关闭对话框
                    if #S.trashDialogList == 0 then
                        M.CancelDialog()
                    end
                    return true
                end
            end
        end
        -- 检查关闭按钮
        if S.trashDialogCloseBtn then
            local cb = S.trashDialogCloseBtn
            if mx >= cb.x and mx < cb.x + cb.w and my >= cb.y and my < cb.y + cb.h then
                M.CancelDialog()
                return true
            end
        end
    end

    -- 点击对话框外部取消
    if mx < dlgX or mx > dlgX + dlgW or my < dlgY or my > dlgY + dlgH then
        M.CancelDialog()
        return true
    end

    return true
end

return M
