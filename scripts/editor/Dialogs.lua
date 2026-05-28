-- ====================================================================
-- editor/Dialogs.lua - 对话框系统（渲染 + 输入 + 逻辑）
-- ====================================================================

local C = require "editor.Constants"
local S = require "editor.State"

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
-- 对话框打开
-- ====================================================================

function M.OpenCanvasDialog()
    S.dialogMode = "canvas"
    S.canvasWidthInput = tostring(S.MAP_COLS)
    S.canvasHeightInput = tostring(S.MAP_ROWS)
    S.canvasFocusField = 1
    S.canvasCursor = #S.canvasWidthInput
    S.renameBlink = 0
end

function M.OpenPlayerDialog()
    S.dialogMode = "player"
    S.playerParamInputs = {
        tostring(S.playerParams.baseJumpGrids),
        tostring(S.playerParams.fallJumpMultiplier),
        tostring(S.playerParams.maxFallGrids),
        tostring(S.playerParams.maxJumpGrids),
        tostring(S.playerParams.defaultLightDiameter),
    }
    S.playerParamFocus = 1
    S.playerParamCursor = #S.playerParamInputs[1]
    S.renameBlink = 0
end

function M.OpenLightDialog(lightIdx)
    S.selectedLightIndex = lightIdx
    local light = FogOfWar.GetLight(lightIdx)
    S.lightDiameterInput = tostring(light.diameter)
    S.lightFeatherInput = tostring(light.feather)
    S.dialogMode = "light"
    S.lightDialogFocus = 1
    S.lightDialogCursor = #S.lightDiameterInput
    S.renameBlink = 0
end

function M.OpenRenameDialog(lv)
    S.dialogMode = "rename"
    S.dialogTarget = lv
    S.renameInput = lv.name
    S.renameCursor = #lv.name
    S.renameBlink = 0
end

function M.OpenDeleteDialog(lv)
    S.dialogMode = "delete"
    S.dialogTarget = lv
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
    S.SetMessage("玩家参数已更新", 1.5)
end

function M.ConfirmDialog()
    if S.dialogMode == "rename" and S.dialogTarget and S.renameInput ~= "" then
        Persistence.RenameLevel(S.dialogTarget.file, S.renameInput)
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
            FogOfWar.UpdateLight(S.selectedLightIndex, d, f)
        end
    end
    S.dialogMode = nil
    S.dialogTarget = nil
end

function M.CancelDialog()
    S.dialogMode = nil
    S.dialogTarget = nil
end

-- ====================================================================
-- 对话框尺寸计算
-- ====================================================================

local function GetDialogSize()
    local w, h = 180, 65
    if S.dialogMode == "rename" then h = 80
    elseif S.dialogMode == "canvas" then h = 100
    elseif S.dialogMode == "player" then w = 200; h = 170
    elseif S.dialogMode == "light" then h = 100
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

    local inputX = dlgX + 12
    local inputY = dlgY + 26
    local inputW = dlgW - 24
    local inputH = 18

    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, 3)
    nvgFillColor(vg, nvgRGBA(15, 15, 25, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, inputX, inputY, inputW, inputH, 3)
    nvgStrokeColor(vg, nvgRGBA(80, 120, 200, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 240, 240, 255))
    nvgText(vg, inputX + 4, inputY + inputH * 0.5, S.renameInput)

    -- 闪烁光标
    if math.floor(S.renameBlink * 2) % 2 == 0 then
        local cursorText = string.sub(S.renameInput, 1, S.renameCursor)
        local bounds = {}
        local tw = nvgTextBounds(vg, 0, 0, cursorText, bounds)
        local cursorX = inputX + 4 + tw
        nvgBeginPath(vg)
        nvgMoveTo(vg, cursorX, inputY + 3)
        nvgLineTo(vg, cursorX, inputY + inputH - 3)
        nvgStrokeColor(vg, nvgRGBA(200, 220, 255, 255))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end

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

    for i = 1, 5 do
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
    nvgText(vg, dlgX + dlgW * 0.5, dlgY + 26, "直径:2~30格  羽化:0.0~1.0")

    local inputW = 50
    local inputH = 16
    local fieldY1 = dlgY + 34
    local fieldY2 = dlgY + 56
    local dInputX = dlgX + dlgW * 0.5 - inputW * 0.5

    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 210, 255))
    nvgText(vg, dInputX - 6, fieldY1 + inputH * 0.5, "直径:")
    nvgText(vg, dInputX - 6, fieldY2 + inputH * 0.5, "羽化:")

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

    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 180))
    nvgText(vg, dInputX + inputW + 6, fieldY1 + inputH * 0.5, "格")

    DrawButtons(vg, dlgX, dlgY, dlgW, dlgH, "确认", 40, 120, 60)
end

-- ====================================================================
-- 主渲染入口
-- ====================================================================

function M.Draw()
    if not S.dialogMode then return end
    local vg = S.vg

    -- 遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, S.screenDesignW, S.screenDesignH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    local dlgX, dlgY, dlgW, dlgH = GetDialogRect()
    DrawDialogFrame(vg, dlgX, dlgY, dlgW, dlgH)
    nvgFontFace(vg, "sans")

    if S.dialogMode == "rename" then
        DrawRenameDialog(vg, dlgX, dlgY, dlgW, dlgH)
    elseif S.dialogMode == "delete" then
        DrawDeleteDialog(vg, dlgX, dlgY, dlgW, dlgH)
    elseif S.dialogMode == "canvas" then
        DrawCanvasDialog(vg, dlgX, dlgY, dlgW, dlgH)
    elseif S.dialogMode == "player" then
        DrawPlayerDialog(vg, dlgX, dlgY, dlgW, dlgH)
    elseif S.dialogMode == "light" then
        DrawLightDialog(vg, dlgX, dlgY, dlgW, dlgH)
    end
end

-- ====================================================================
-- 键盘输入处理
-- ====================================================================

local function HandleRenameKey(key)
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
        M.CancelDialog()
        return true
    end

    if key == KEY_RETURN or key == KEY_KP_ENTER then
        M.ConfirmDialog()
        return true
    end

    if key == KEY_TAB then
        if S.dialogMode == "light" then
            if S.lightDialogFocus == 1 then
                S.lightDialogFocus = 2
                S.lightDialogCursor = #S.lightFeatherInput
            else
                S.lightDialogFocus = 1
                S.lightDialogCursor = #S.lightDiameterInput
            end
            S.renameBlink = 0
        elseif S.dialogMode == "player" then
            S.playerParamFocus = (S.playerParamFocus % 5) + 1
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
        end
        return true
    end

    if S.dialogMode == "rename" then
        HandleRenameKey(key)
    elseif S.dialogMode == "canvas" then
        local cur = (S.canvasFocusField == 1) and S.canvasWidthInput or S.canvasHeightInput
        cur, S.canvasCursor = HandleNumericFieldKey(key, cur, S.canvasCursor)
        if S.canvasFocusField == 1 then S.canvasWidthInput = cur else S.canvasHeightInput = cur end
    elseif S.dialogMode == "player" then
        local cur = S.playerParamInputs[S.playerParamFocus]
        cur, S.playerParamCursor = HandleNumericFieldKey(key, cur, S.playerParamCursor)
        S.playerParamInputs[S.playerParamFocus] = cur
    elseif S.dialogMode == "light" then
        local cur = (S.lightDialogFocus == 1) and S.lightDiameterInput or S.lightFeatherInput
        cur, S.lightDialogCursor = HandleNumericFieldKey(key, cur, S.lightDialogCursor)
        if S.lightDialogFocus == 1 then S.lightDiameterInput = cur else S.lightFeatherInput = cur end
    end

    return true
end

-- ====================================================================
-- 文本输入处理
-- ====================================================================

function M.HandleTextInput(text)
    if not S.dialogMode then return false end
    if not text or #text == 0 then return true end

    if S.dialogMode == "rename" then
        if #S.renameInput < 60 then
            S.renameInput = string.sub(S.renameInput, 1, S.renameCursor) .. text .. string.sub(S.renameInput, S.renameCursor + 1)
            S.renameCursor = S.renameCursor + #text
            S.renameBlink = 0
        end
    elseif S.dialogMode == "canvas" then
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
            local cur = (S.lightDialogFocus == 1) and S.lightDiameterInput or S.lightFeatherInput
            if #cur < 5 then
                cur = string.sub(cur, 1, S.lightDialogCursor) .. valid .. string.sub(cur, S.lightDialogCursor + 1)
                S.lightDialogCursor = S.lightDialogCursor + #valid
                S.renameBlink = 0
                if S.lightDialogFocus == 1 then S.lightDiameterInput = cur else S.lightFeatherInput = cur end
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
        end
    elseif S.dialogMode == "player" then
        local inputW = 50
        local inputH = 14
        local startY = dlgY + 28
        local rowGap = 20
        local inputX = dlgX + dlgW * 0.5 - inputW * 0.5
        for i = 1, 5 do
            local fieldY = startY + (i - 1) * rowGap
            if mx >= inputX and mx < inputX + inputW and my >= fieldY and my < fieldY + inputH then
                S.playerParamFocus = i; S.playerParamCursor = #S.playerParamInputs[i]; S.renameBlink = 0
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
