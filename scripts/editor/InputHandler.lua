-- ====================================================================
-- editor/InputHandler.lua - 输入事件路由与处理
-- ====================================================================

local C = require "editor.Constants"
local S = require "editor.State"
local TileUtils = require "editor.TileUtils"
local Undo = require "editor.UndoSystem"
local Placement = require "editor.Placement"

local TILE = C.TILE
local MODE = C.MODE
local INTERACT = C.INTERACT
local BOUND_EDGE = C.BOUND_EDGE
local GRID = C.GRID
local TOPBAR_H = C.TOPBAR_H
local BOTTOMBAR_H = C.BOTTOMBAR_H
local SIDEBAR_W = C.SIDEBAR_W
local ZOOM_FACTOR = C.ZOOM_FACTOR
local ZOOM_MIN = C.ZOOM_MIN
local ZOOM_MAX = C.ZOOM_MAX
local TOOLS = C.TOOLS
local LIGHT_TOOL_INDEX = 9

local M = {}

-- ====================================================================
-- 外部依赖（通过 Inject 注入）
-- ====================================================================
local Dialogs = nil
local Persistence = nil
local PlayMode = nil
local FogOfWar = nil
local WorldMapEditor = nil
local MapData = nil

function M.Inject(deps)
    Dialogs = deps.Dialogs
    Persistence = deps.Persistence
    PlayMode = deps.PlayMode
    FogOfWar = deps.FogOfWar
    WorldMapEditor = deps.WorldMapEditor
    MapData = deps.MapData
end

-- ====================================================================
-- 辅助函数
-- ====================================================================

local function GetDesignMouse()
    local mx = input:GetMousePosition().x / S.dpr / S.scaleF
    local my = input:GetMousePosition().y / S.dpr / S.scaleF
    return mx, my
end

local function ScreenToGrid(mx, my)
    return TileUtils.ScreenToGrid(mx, my, S.cameraX, S.cameraY, S.zoomLevel)
end

local function IsTileSelectable(col, row)
    return TileUtils.IsTileSelectable(S.levelData, col, row, S.MAP_COLS, S.MAP_ROWS)
end

local function GetTileType(val)
    return TileUtils.GetTileType(val)
end

local function CycleDifficulty()
    local diffs = C.DIFFICULTIES
    for i, d in ipairs(diffs) do
        if d.id == S.currentDifficulty then
            local next = (i % #diffs) + 1
            S.currentDifficulty = diffs[next].id
            S.SetMessage("难度: " .. diffs[next].name, 1.5)
            return
        end
    end
    S.currentDifficulty = diffs[1].id
end

local function SwitchToHiddenWallTool(idx, prevTool)
    local hiddenWallToolIdx = 8
    if idx == hiddenWallToolIdx and prevTool ~= hiddenWallToolIdx then
        if S.hiddenWall.lastEditTime > 0 then
            S.hiddenWall.group = S.hiddenWall.group + 1
        end
        S.hiddenWall.lastEditTime = S.editorClock
    end
end

-- ====================================================================
-- HandleUpdate (编辑模式帧更新)
-- ====================================================================

function M.HandleUpdate(dt)
    -- 对话框打开时不处理编辑器键盘输入
    if S.dialogMode then
        UpdateAutoSave(dt)
        return
    end

    -- WASD 相机移动
    local scrollSpeed = 200
    if input:GetKeyDown(KEY_A) and not input:GetKeyDown(KEY_CTRL) then
        S.cameraX = S.cameraX - scrollSpeed * dt
    end
    if input:GetKeyDown(KEY_D) and not input:GetKeyDown(KEY_CTRL) then
        S.cameraX = S.cameraX + scrollSpeed * dt
    end
    if input:GetKeyDown(KEY_W) and not input:GetKeyDown(KEY_CTRL) then
        S.cameraY = S.cameraY - scrollSpeed * dt
    end
    if input:GetKeyDown(KEY_S) and not input:GetKeyDown(KEY_CTRL) then
        S.cameraY = S.cameraY + scrollSpeed * dt
    end

    -- 中键拖拽视窗
    if S.midDragging then
        local mx, my = GetDesignMouse()
        local dx = mx - S.midDragLastX
        local dy = my - S.midDragLastY
        S.cameraX = S.cameraX - dx
        S.cameraY = S.cameraY - dy
        S.midDragLastX = mx
        S.midDragLastY = my
    end

    ClampCamera()
    UpdateBoundDrag()
    UpdateMoveDrag()
    UpdateBoxSelect()
    UpdateDrawErase()
    UpdateAutoSave(dt)
end

function ClampCamera()
    local zGrid = GRID * S.zoomLevel
    local mapW = S.screenDesignW - (S.sidebarOpen and SIDEBAR_W or 0)
    local mapH = S.screenDesignH - TOPBAR_H - BOTTOMBAR_H
    local maxCamX = math.max(0, S.MAP_COLS * zGrid - mapW)
    local maxCamY = math.max(0, S.MAP_ROWS * zGrid - mapH)
    S.cameraX = math.max(-mapW * 0.3, math.min(S.cameraX, maxCamX + mapW * 0.3))
    S.cameraY = math.max(-mapH * 0.3, math.min(S.cameraY, maxCamY + mapH * 0.3))
end

function UpdateBoundDrag()
    if not S.boundDragActive then return end
    local mx, my = GetDesignMouse()
    local gridCol, gridRow = ScreenToGrid(mx, my)
    gridCol = math.max(1, math.min(gridCol, S.MAP_COLS))
    gridRow = math.max(1, math.min(gridRow, S.MAP_ROWS))

    if S.boundDragEdge == BOUND_EDGE.RIGHT then
        S.camBound.right = math.max(S.camBound.left + 1, gridCol)
    elseif S.boundDragEdge == BOUND_EDGE.LEFT then
        S.camBound.left = math.min(S.camBound.right - 1, gridCol)
    elseif S.boundDragEdge == BOUND_EDGE.BOTTOM then
        S.camBound.bottom = math.max(S.camBound.top + 1, gridRow)
    elseif S.boundDragEdge == BOUND_EDGE.TOP then
        S.camBound.top = math.min(S.camBound.bottom - 1, gridRow)
    end
end

function UpdateMoveDrag()
    if not S.moveDragging then return end
    local mx, my = GetDesignMouse()
    local col, row = ScreenToGrid(mx, my)
    col = math.max(1, math.min(S.MAP_COLS, col))
    row = math.max(1, math.min(S.MAP_ROWS, row))
    S.moveDragCurrentCol = col
    S.moveDragCurrentRow = row
end

function UpdateBoxSelect()
    if not S.boxSelectActive then return end
    local mx, my = GetDesignMouse()
    S.boxSelectCurrentX = mx
    S.boxSelectCurrentY = my
end

function UpdateDrawErase()
    if (not S.isDrawing and not S.isErasing) or S.boundDragActive then return end
    local mx, my = GetDesignMouse()
    local mapRight = S.screenDesignW - (S.sidebarOpen and SIDEBAR_W or 0)
    if mx < 0 or mx >= mapRight or my >= S.screenDesignH - BOTTOMBAR_H then return end

    local col, row = ScreenToGrid(mx, my)
    if col == S.lastPlacedCol and row == S.lastPlacedRow then return end
    if col < 1 or col > S.MAP_COLS or row < 1 or row > S.MAP_ROWS then return end

    if S.isDrawing then
        Placement.PlaceTile(col, row)
    else
        Placement.EraseTile(col, row)
    end
    S.lastPlacedCol = col
    S.lastPlacedRow = row
end

function UpdateAutoSave(dt)
    if Undo.saveTimer <= 0 then return end
    Undo.saveTimer = Undo.saveTimer - dt
    if Undo.saveTimer <= 0 then
        Undo.saveTimer = 0
        Persistence.TryAutoSave()
    end
end

-- ====================================================================
-- HandleKeyDown
-- ====================================================================

function M.HandleKeyDown(key)
    -- 试玩模式
    if S.editorMode == MODE.PLAY then
        HandlePlayModeKey(key)
        return
    end
    if S.editorMode == MODE.WORLDPLAY then
        HandleWorldPlayModeKey(key)
        return
    end
    if S.editorMode == MODE.WORLDMAP then
        HandleWorldMapKey(key)
        return
    end

    -- 对话框
    if S.dialogMode then
        Dialogs.HandleKeyDown(key)
        return
    end

    -- 编辑模式
    HandleEditorKey(key)
end

function HandlePlayModeKey(key)
    if key == KEY_ESCAPE then
        S.editorMode = MODE.EDIT
        S.SetMessage("返回编辑模式", 1.5)
    elseif key == KEY_R then
        PlayMode.StartPlayMode()
    end
end

function HandleWorldPlayModeKey(key)
    if key == KEY_ESCAPE then
        S.editorMode = MODE.WORLDMAP
        WorldMapEditor.SetLayout(S.screenDesignW, S.screenDesignH, TOPBAR_H, 0, S.sidebarOpen and SIDEBAR_W or 0)
        S.SetMessage("返回世界地图编辑", 1.5)
    elseif key == KEY_R then
        PlayMode.StartWorldPlayMode()
    end
end

function HandleWorldMapKey(key)
    if key == KEY_ESCAPE then
        S.editorMode = MODE.EDIT
        S.SetMessage("返回编辑模式", 1.5)
        return
    end
    WorldMapEditor.HandleKeyDown(key)
end

function HandleEditorKey(key)
    -- 交互模式快捷键
    if key == KEY_R then
        S.interactMode = INTERACT.DRAW
        S.SetMessage("模式: 绘制", 1.0)
        return
    end
    if key == KEY_Q then
        S.interactMode = INTERACT.SELECT
        S.SetMessage("模式: 选取", 1.0)
        return
    end
    if key == KEY_E then
        S.interactMode = INTERACT.MOVE
        S.SetMessage("模式: 移动", 1.0)
        return
    end

    -- 工具数字键
    if key >= KEY_1 and key <= KEY_9 then
        local idx = key - KEY_1 + 1
        if idx <= #TOOLS then
            local prevTool = S.currentTool
            S.currentTool = idx
            S.interactMode = INTERACT.DRAW
            SwitchToHiddenWallTool(idx, prevTool)
        end
        return
    end

    -- 功能键
    if key == KEY_F then
        S.fogShowInEditor = not S.fogShowInEditor
        S.SetMessage(S.fogShowInEditor and "迷雾: 开启" or "迷雾: 关闭", 1.5)
    elseif key == KEY_G then
        S.currentGroup = S.currentGroup % C.MAX_GROUPS + 1
        S.SetMessage("颜色组:" .. C.GROUP_NAMES[S.currentGroup], 1.5)
    elseif key == KEY_T then
        CycleDifficulty()
    elseif key == KEY_P then
        Persistence.AutoSaveBeforeSwitch()
        PlayMode.StartPlayMode()
    elseif key == KEY_Z then
        Undo.Undo()
    elseif key == KEY_S and input:GetKeyDown(KEY_CTRL) then
        Persistence.SaveLevel()
        Undo.dirty = false
    elseif key == KEY_L and input:GetKeyDown(KEY_CTRL) then
        S.sidebarOpen = not S.sidebarOpen
    elseif key == KEY_ESCAPE then
        Persistence.AutoSaveBeforeSwitch()
        engine:Exit()
    end
end

-- ====================================================================
-- HandleTextInput
-- ====================================================================

function M.HandleTextInput(text)
    if S.dialogMode then
        Dialogs.HandleTextInput(text)
    end
end

-- ====================================================================
-- HandleTextEditing (IME 组合输入)
-- ====================================================================

function M.HandleTextEditing(composition, cursor, selectionLength)
    if S.dialogMode then
        Dialogs.HandleTextEditing(composition, cursor, selectionLength)
    end
end

-- ====================================================================
-- HandleMouseDown
-- ====================================================================

function M.HandleMouseDown(button, mx, my)
    -- 试玩模式
    if S.editorMode == MODE.PLAY then
        HandlePlayModeClick(button, mx, my)
        return
    end
    if S.editorMode == MODE.WORLDPLAY then
        HandleWorldPlayClick(button, mx, my)
        return
    end
    if S.editorMode == MODE.WORLDMAP then
        HandleWorldMapClick(button, mx, my)
        return
    end

    -- 对话框（优先，阻塞其他交互）
    if S.dialogMode and button == MOUSEB_LEFT then
        Dialogs.HandleMouseDown(mx, my)
        return
    end

    -- 顶栏
    if my < TOPBAR_H and button == MOUSEB_LEFT then
        HandleTopBarClick(mx, my)
        return
    end

    -- 侧边栏
    if S.sidebarOpen and mx >= S.screenDesignW - SIDEBAR_W and my > TOPBAR_H and my < S.screenDesignH - BOTTOMBAR_H then
        if button == MOUSEB_LEFT then
            HandleSidebarClick(mx, my)
        end
        return
    end

    -- 底部工具栏
    local barY = S.screenDesignH - BOTTOMBAR_H
    if my >= barY and my < S.screenDesignH - 16 and button == MOUSEB_LEFT then
        HandleToolbarClick(mx, my, barY)
        return
    end

    -- 中键拖拽视窗
    if button == MOUSEB_MIDDLE then
        S.midDragging = true
        S.midDragLastX = mx
        S.midDragLastY = my
        return
    end

    -- 地图区域
    local mapRight = S.screenDesignW - (S.sidebarOpen and SIDEBAR_W or 0)
    if mx >= 0 and mx < mapRight and my >= TOPBAR_H and my < S.screenDesignH - BOTTOMBAR_H then
        HandleMapClick(button, mx, my)
    end
end

function HandlePlayModeClick(button, mx, my)
    if button ~= MOUSEB_LEFT then return end
    local backBtnW, backBtnH = 50, 16
    local backBtnX = S.screenDesignW - backBtnW - 6
    local backBtnY = (22 - backBtnH) * 0.5
    local pad = 6
    if mx >= backBtnX - pad and mx < backBtnX + backBtnW + pad and my >= backBtnY - pad and my < backBtnY + backBtnH + pad then
        S.editorMode = MODE.EDIT
        S.SetMessage("返回编辑模式", 1.5)
    end
end

function HandleWorldPlayClick(button, mx, my)
    if button ~= MOUSEB_LEFT then return end
    local backBtnW, backBtnH = 60, 16
    local backBtnX = S.screenDesignW - backBtnW - 6
    local backBtnY = (22 - backBtnH) * 0.5
    local pad = 6
    if mx >= backBtnX - pad and mx < backBtnX + backBtnW + pad and my >= backBtnY - pad and my < backBtnY + backBtnH + pad then
        S.editorMode = MODE.WORLDMAP
        WorldMapEditor.SetLayout(S.screenDesignW, S.screenDesignH, TOPBAR_H, 0, S.sidebarOpen and SIDEBAR_W or 0)
        S.SetMessage("返回世界地图编辑", 1.5)
    end
end

function HandleWorldMapClick(button, mx, my)
    -- 顶栏按钮
    if my < TOPBAR_H and button == MOUSEB_LEFT then
        for _, btn in ipairs(S.topBarButtons) do
            if mx >= btn.x and mx < btn.x + btn.w and my >= btn.y and my < btn.y + btn.h then
                HandleWorldMapTopBarBtn(btn.id)
                return
            end
        end
        return
    end

    -- 侧边栏 → 添加节点
    if S.sidebarOpen and mx >= S.screenDesignW - SIDEBAR_W and my > TOPBAR_H and my < S.screenDesignH then
        if button == MOUSEB_LEFT then
            local sbY = TOPBAR_H
            local itemH = 22
            local listY = sbY + 24 - S.sidebarScroll
            for i, lv in ipairs(S.savedLevels) do
                local iy = listY + (i - 1) * itemH
                if my >= iy and my < iy + itemH then
                    WorldMapEditor.AddNode(lv.file, lv.name)
                    return
                end
            end
        end
        return
    end

    -- 地图区域委托
    WorldMapEditor.HandleMouseDown(button, mx, my)
end

function HandleWorldMapTopBarBtn(id)
    if id == "worldmap" then
        S.editorMode = MODE.EDIT
        S.SetMessage("返回编辑模式", 1.5)
    elseif id == "play" then
        PlayMode.StartWorldPlayMode()
    elseif id == "save" then
        WorldMapEditor.Save()
    elseif id == "sidebar" then
        S.sidebarOpen = not S.sidebarOpen
    end
end

function HandleTopBarClick(mx, my)
    for _, btn in ipairs(S.topBarButtons) do
        if mx >= btn.x and mx < btn.x + btn.w and my >= btn.y and my < btn.y + btn.h then
            DispatchTopBarBtn(btn.id)
            return
        end
    end
end

function DispatchTopBarBtn(id)
    if id == "save" then
        Persistence.SaveLevel()
    elseif id == "saveNew" then
        Persistence.SaveAsNewLevel()
    elseif id == "canvas" then
        Dialogs.OpenCanvasDialog()
    elseif id == "player" then
        Dialogs.OpenPlayerDialog()
    elseif id == "fog" then
        S.fogShowInEditor = not S.fogShowInEditor
        S.SetMessage(S.fogShowInEditor and "迷雾: 开启" or "迷雾: 关闭", 1.5)
    elseif id == "random" then
        Persistence.AutoSaveBeforeSwitch()
        PlayMode.GenerateRandomLevel()
    elseif id == "play" then
        Persistence.AutoSaveBeforeSwitch()
        PlayMode.StartPlayMode()
    elseif id == "worldmap" then
        Persistence.AutoSaveBeforeSwitch()
        S.editorMode = MODE.WORLDMAP
        WorldMapEditor.SetLayout(S.screenDesignW, S.screenDesignH, TOPBAR_H, 0, S.sidebarOpen and SIDEBAR_W or 0)
        S.SetMessage("世界地图编辑模式", 2.0)
    elseif id == "sidebar" then
        S.sidebarOpen = not S.sidebarOpen
    end
end

local SIDEBAR_DOUBLE_CLICK_TIME = 0.4  -- 双击判定时间窗口（秒）

function HandleSidebarClick(mx, my)
    local sbX = S.screenDesignW - SIDEBAR_W
    local sbY = TOPBAR_H
    local itemH = 22
    local actionBtnSize = 14
    local listY = sbY + 24 - S.sidebarScroll

    for i, lv in ipairs(S.savedLevels) do
        local iy = listY + (i - 1) * itemH
        if my >= iy and my < iy + itemH then
            local btnY2 = iy + (itemH - actionBtnSize) * 0.5
            local delX = sbX + SIDEBAR_W - 8 - actionBtnSize
            local renX = delX - actionBtnSize - 2

            if mx >= delX and mx < delX + actionBtnSize and my >= btnY2 and my < btnY2 + actionBtnSize then
                Dialogs.OpenDeleteDialog(lv)
                return
            end
            if mx >= renX and mx < renX + actionBtnSize and my >= btnY2 and my < btnY2 + actionBtnSize then
                Dialogs.OpenRenameDialog(lv)
                return
            end

            -- 双击检测：同一关卡在时间窗口内被点击两次 → 进入编辑
            local now = os.clock()
            if S.sidebarLastClickFile == lv.file and (now - S.sidebarLastClickTime) < SIDEBAR_DOUBLE_CLICK_TIME then
                -- 双击：进入关卡编辑
                S.sidebarLastClickFile = nil
                S.sidebarLastClickTime = 0
                Persistence.AutoSaveBeforeSwitch()
                Persistence.LoadLevel(lv.file)
                S.SetMessage("编辑关卡: " .. lv.name, 2.0)
            else
                -- 单击：记录点击状态（用于双击检测）
                S.sidebarLastClickFile = lv.file
                S.sidebarLastClickTime = now
            end
            return
        end
    end
end

function HandleToolbarClick(mx, my, barY)
    -- 交互模式按钮
    local modeBtnW, modeBtnH, modeBtnPad = 20, 11, 2
    local modeBtnStartX, modeBtnStartY = 6, barY + 3
    for i = 1, 3 do
        local mbx = modeBtnStartX
        local mby = modeBtnStartY + (i - 1) * (modeBtnH + modeBtnPad)
        if mx >= mbx and mx < mbx + modeBtnW and my >= mby and my < mby + modeBtnH then
            S.interactMode = i
            if i ~= INTERACT.SELECT and i ~= INTERACT.MOVE then
                S.ClearSelection()
            end
            return
        end
    end

    -- 工具按钮
    local btnW, btnH, btnPad = 36, 28, 4
    local totalW = #TOOLS * (btnW + btnPad) - btnPad
    local startX = (S.screenDesignW - totalW) * 0.5
    local toolBarH = BOTTOMBAR_H - 16
    local btnY = barY + (toolBarH - btnH) * 0.5
    for i = 1, #TOOLS do
        local bx = startX + (i - 1) * (btnW + btnPad)
        if mx >= bx and mx < bx + btnW and my >= btnY and my < btnY + btnH then
            local prevTool = S.currentTool
            S.currentTool = i
            S.interactMode = INTERACT.DRAW
            SwitchToHiddenWallTool(i, prevTool)
            S.ClearSelection()
            return
        end
    end
end

-- ====================================================================
-- 地图区域点击
-- ====================================================================

function HandleMapClick(button, mx, my)
    -- 边界拖拽（仅绘制模式左键）
    if S.interactMode == INTERACT.DRAW and button == MOUSEB_LEFT then
        local edge = TileUtils.DetectBoundEdge(mx, my, S.camBound, S.cameraX, S.cameraY, S.zoomLevel, S.screenDesignW, S.screenDesignH, S.sidebarOpen)
        if edge ~= BOUND_EDGE.NONE then
            S.boundDragActive = true
            S.boundDragEdge = edge
            return
        end
    end

    local col, row = ScreenToGrid(mx, my)
    if col < 1 or col > S.MAP_COLS or row < 1 or row > S.MAP_ROWS then return end

    if S.interactMode == INTERACT.SELECT then
        HandleSelectClick(button, mx, my, col, row)
    elseif S.interactMode == INTERACT.MOVE then
        HandleMoveClick(button, col, row)
    else
        HandleDrawClick(button, col, row)
    end
end

function HandleSelectClick(button, mx, my, col, row)
    if button == MOUSEB_LEFT then
        S.boxSelectActive = true
        S.boxSelectStartX = mx
        S.boxSelectStartY = my
        S.boxSelectCurrentX = mx
        S.boxSelectCurrentY = my
    elseif button == MOUSEB_RIGHT then
        S.ClearSelection()
    end
end

function HandleMoveClick(button, col, row)
    if button == MOUSEB_LEFT then
        HandleMoveStart(col, row)
    elseif button == MOUSEB_RIGHT then
        S.ClearSelection()
        S.moveDragging = false
        S.multiMoving = false
    end
end

function HandleMoveStart(col, row)
    -- 检查是否点击了多选列表中的物体
    local clickedInMultiSelect = false
    if #S.selectedTiles > 0 then
        for _, st in ipairs(S.selectedTiles) do
            if st.col == col and st.row == row then
                clickedInMultiSelect = true
                break
            end
        end
    end

    if clickedInMultiSelect then
        StartMultiMove(col, row)
    else
        StartSingleMove(col, row)
    end
end

function StartMultiMove(col, row)
    S.multiMoving = true
    S.moveDragging = true
    S.moveDragStartCol = col
    S.moveDragStartRow = row
    S.moveDragCurrentCol = col
    S.moveDragCurrentRow = row
    S.moveDragTileValue = 0
    S.moveDragLightIdx = 0
end

function StartSingleMove(col, row)
    S.multiMoving = false
    local lightIdx = FogOfWar.FindLight(col, row)
    if lightIdx then
        S.selectedTileCol = col
        S.selectedTileRow = row
        S.selectedIsLight = true
        S.selectedLightIndex = lightIdx
        InitMoveDrag(col, row, 0, lightIdx)
    elseif IsTileSelectable(col, row) then
        S.selectedTileCol = col
        S.selectedTileRow = row
        S.selectedIsLight = false
        InitMoveDrag(col, row, S.levelData[row][col], 0)
    else
        S.ClearSelection()
    end
end

function InitMoveDrag(col, row, tileValue, lightIdx)
    S.moveDragging = true
    S.moveDragStartCol = col
    S.moveDragStartRow = row
    S.moveDragCurrentCol = col
    S.moveDragCurrentRow = row
    S.moveDragTileValue = tileValue
    S.moveDragLightIdx = lightIdx
end

function HandleDrawClick(button, col, row)
    -- 光源工具
    if S.currentTool == LIGHT_TOOL_INDEX then
        HandleLightToolClick(button, col, row)
        return
    end

    -- 普通地块工具
    if button == MOUSEB_LEFT then
        S.isDrawing = true; S.isErasing = false
        Placement.PlaceTile(col, row)
        S.lastPlacedCol = col; S.lastPlacedRow = row
    elseif button == MOUSEB_RIGHT then
        S.isErasing = true; S.isDrawing = false
        Placement.EraseTile(col, row)
        S.lastPlacedCol = col; S.lastPlacedRow = row
    end
end

function HandleLightToolClick(button, col, row)
    if button == MOUSEB_LEFT then
        local existIdx = FogOfWar.FindLight(col, row)
        if existIdx then
            Dialogs.OpenLightDialog(existIdx)
        else
            local idx = FogOfWar.AddLight(col, row, 6, 0.5)
            S.selectedLightIndex = idx
            S.lightSources = FogOfWar.GetLightSources()
            Undo.dirty = true
            Undo.saveTimer = Undo.saveDelay
            S.SetMessage("放置光源 (" .. col .. "," .. row .. ")", 1.5)
            Dialogs.OpenLightDialog(idx)
        end
    elseif button == MOUSEB_RIGHT then
        local removed = FogOfWar.RemoveLight(col, row)
        if removed then
            S.lightSources = FogOfWar.GetLightSources()
            S.selectedLightIndex = 0
            S.dialogMode = nil
            Undo.dirty = true
            Undo.saveTimer = Undo.saveDelay
            S.SetMessage("删除光源", 1.5)
        end
    end
end

-- ====================================================================
-- HandleMouseUp
-- ====================================================================

function M.HandleMouseUp(button, mx, my)
    if S.editorMode == MODE.PLAY or S.editorMode == MODE.WORLDPLAY then return end

    if S.editorMode == MODE.WORLDMAP then
        WorldMapEditor.HandleMouseUp(button, mx, my)
        return
    end

    if button == MOUSEB_MIDDLE then
        S.midDragging = false
        return
    end

    if button == MOUSEB_LEFT then
        HandleLeftRelease(mx, my)
    elseif button == MOUSEB_RIGHT then
        if S.isErasing then
            Undo.FinalizeDrawAction()
        end
        S.isErasing = false
    end
    S.lastPlacedCol = -1
    S.lastPlacedRow = -1
end

function HandleLeftRelease(mx, my)
    if S.boxSelectActive then
        FinishBoxSelect(mx, my)
        return
    end

    if S.moveDragging then
        FinishMoveDrag(mx, my)
        return
    end

    if S.isDrawing then
        Undo.FinalizeDrawAction()
    end
    S.isDrawing = false

    if S.boundDragActive then
        S.boundDragActive = false
        S.boundDragEdge = BOUND_EDGE.NONE
    end
end

-- ====================================================================
-- 框选完成
-- ====================================================================

function FinishBoxSelect(mx, my)
    S.boxSelectActive = false
    local dx = math.abs(S.boxSelectCurrentX - S.boxSelectStartX)
    local dy = math.abs(S.boxSelectCurrentY - S.boxSelectStartY)

    if dx > C.BOX_SELECT_THRESHOLD or dy > C.BOX_SELECT_THRESHOLD then
        CollectBoxSelection()
    else
        ClickSelect()
    end
end

function CollectBoxSelection()
    local c1, r1 = ScreenToGrid(
        math.min(S.boxSelectStartX, S.boxSelectCurrentX),
        math.min(S.boxSelectStartY, S.boxSelectCurrentY))
    local c2, r2 = ScreenToGrid(
        math.max(S.boxSelectStartX, S.boxSelectCurrentX),
        math.max(S.boxSelectStartY, S.boxSelectCurrentY))
    c1 = math.max(1, math.min(S.MAP_COLS, c1))
    c2 = math.max(1, math.min(S.MAP_COLS, c2))
    r1 = math.max(1, math.min(S.MAP_ROWS, r1))
    r2 = math.max(1, math.min(S.MAP_ROWS, r2))

    local toolTile = TOOLS[S.currentTool] and TOOLS[S.currentTool].tile or 0
    local priorityList, otherList = {}, {}

    CollectLightsInRange(c1, r1, c2, r2, toolTile, priorityList, otherList)
    CollectTilesInRange(c1, r1, c2, r2, toolTile, priorityList, otherList)

    S.selectedTiles = #priorityList > 0 and priorityList or otherList
    if #S.selectedTiles > 0 then
        local first = S.selectedTiles[1]
        S.selectedTileCol = first.col
        S.selectedTileRow = first.row
        S.selectedIsLight = first.isLight
        if first.isLight then S.selectedLightIndex = first.lightIdx end
        S.SetMessage("框选 " .. #S.selectedTiles .. " 个物体", 1.5)
    else
        S.ClearSelection()
    end
end

function CollectLightsInRange(c1, r1, c2, r2, toolTile, priorityList, otherList)
    local lights = FogOfWar.GetLightSources()
    for idx, lt in ipairs(lights) do
        if lt.col >= c1 and lt.col <= c2 and lt.row >= r1 and lt.row <= r2 then
            local entry = { col = lt.col, row = lt.row, isLight = true, lightIdx = idx }
            if toolTile == -1 then
                priorityList[#priorityList + 1] = entry
            else
                otherList[#otherList + 1] = entry
            end
        end
    end
end

function CollectTilesInRange(c1, r1, c2, r2, toolTile, priorityList, otherList)
    for row = r1, r2 do
        for col = c1, c2 do
            if IsTileSelectable(col, row) then
                local val = S.levelData[row][col]
                local base = GetTileType(val)
                local entry = { col = col, row = row, isLight = false, lightIdx = 0 }
                if base == toolTile then
                    priorityList[#priorityList + 1] = entry
                else
                    otherList[#otherList + 1] = entry
                end
            end
        end
    end
end

function ClickSelect()
    local col, row = ScreenToGrid(S.boxSelectStartX, S.boxSelectStartY)
    if col < 1 or col > S.MAP_COLS or row < 1 or row > S.MAP_ROWS then
        S.ClearSelection()
        return
    end

    local lightIdx = FogOfWar.FindLight(col, row)
    if lightIdx then
        S.selectedTileCol = col
        S.selectedTileRow = row
        S.selectedIsLight = true
        S.selectedLightIndex = lightIdx
        S.selectedTiles = {{ col = col, row = row, isLight = true, lightIdx = lightIdx }}
        S.SetMessage("选中光源 (" .. col .. "," .. row .. ")", 1.5)
    elseif IsTileSelectable(col, row) then
        S.selectedTileCol = col
        S.selectedTileRow = row
        S.selectedIsLight = false
        S.selectedTiles = {{ col = col, row = row, isLight = false, lightIdx = 0 }}
        local base = GetTileType(S.levelData[row][col])
        local names = { [TILE.SPAWN]="主角", [TILE.FUEL]="火焰", [TILE.GOAL]="终点",
                        [TILE.SPIKE]="刺", [TILE.SWITCH]="开关", [TILE.GATE]="门" }
        S.SetMessage("选中: " .. (names[base] or "物体") .. " (" .. col .. "," .. row .. ")", 1.5)
    else
        S.ClearSelection()
    end
end

-- ====================================================================
-- 移动拖拽完成
-- ====================================================================

function FinishMoveDrag(mx, my)
    local col, row = ScreenToGrid(mx, my)
    col = math.max(1, math.min(S.MAP_COLS, col))
    row = math.max(1, math.min(S.MAP_ROWS, row))

    if col ~= S.moveDragStartCol or row ~= S.moveDragStartRow then
        if S.multiMoving and #S.selectedTiles > 0 then
            ExecuteMultiMove(col, row)
        elseif S.moveDragLightIdx > 0 then
            ExecuteLightMove(col, row)
        else
            ExecuteSingleTileMove(col, row)
        end
    end

    S.moveDragging = false
    S.multiMoving = false
end

function ExecuteMultiMove(targetCol, targetRow)
    local offsetCol = targetCol - S.moveDragStartCol
    local offsetRow = targetRow - S.moveDragStartRow

    -- 建立已选位置集合
    local selectedSet = {}
    for _, st in ipairs(S.selectedTiles) do
        selectedSet[st.row * 10000 + st.col] = true
    end

    -- 检查目标有效性
    if not ValidateMultiMoveTargets(offsetCol, offsetRow, selectedSet) then
        S.SetMessage("目标位置被占用，无法移动", 1.5)
        S.moveDragging = false
        S.multiMoving = false
        return
    end

    -- 收集原始值
    local tileValues = {}
    for i, st in ipairs(S.selectedTiles) do
        if not st.isLight then
            tileValues[i] = S.levelData[st.row][st.col]
        end
    end

    -- 清除原位置
    for i, st in ipairs(S.selectedTiles) do
        if not st.isLight and tileValues[i] then
            Undo.RecordTileChange(st.col, st.row, tileValues[i], TILE.EMPTY)
            S.levelData[st.row][st.col] = TILE.EMPTY
        end
    end

    -- 放置到新位置
    for i, st in ipairs(S.selectedTiles) do
        local nc = st.col + offsetCol
        local nr = st.row + offsetRow
        if st.isLight then
            FogOfWar.MoveLight(st.lightIdx, nc, nr)
        else
            S.levelData[nr][nc] = tileValues[i]
            Undo.RecordTileChange(nc, nr, TILE.EMPTY, tileValues[i])
            if GetTileType(tileValues[i]) == TILE.SPAWN then
                S.spawnCol = nc
                S.spawnRow = nr
            end
        end
    end

    -- 更新坐标
    for _, st in ipairs(S.selectedTiles) do
        st.col = st.col + offsetCol
        st.row = st.row + offsetRow
    end
    S.lightSources = FogOfWar.GetLightSources()
    Undo.dirty = true
    Undo.saveTimer = Undo.saveDelay
    S.SetMessage(#S.selectedTiles .. " 个物体已移动", 1.5)
end

function ValidateMultiMoveTargets(offsetCol, offsetRow, selectedSet)
    for _, st in ipairs(S.selectedTiles) do
        local nc = st.col + offsetCol
        local nr = st.row + offsetRow
        if nc < 1 or nc > S.MAP_COLS or nr < 1 or nr > S.MAP_ROWS then
            return false
        end
        if not st.isLight then
            local destVal = S.levelData[nr][nc]
            if destVal ~= TILE.EMPTY and not selectedSet[nr * 10000 + nc] then
                return false
            end
        end
    end
    return true
end

function ExecuteLightMove(col, row)
    FogOfWar.MoveLight(S.moveDragLightIdx, col, row)
    S.lightSources = FogOfWar.GetLightSources()
    S.selectedTileCol = col
    S.selectedTileRow = row
    Undo.dirty = true
    Undo.saveTimer = Undo.saveDelay
    S.SetMessage("光源已移动到 (" .. col .. "," .. row .. ")", 1.5)
end

function ExecuteSingleTileMove(col, row)
    local oldVal = S.moveDragTileValue
    local destVal = S.levelData[row][col]
    if destVal ~= TILE.EMPTY and not (row == S.moveDragStartRow and col == S.moveDragStartCol) then
        S.SetMessage("目标位置已被占用", 1.5)
        return
    end

    S.levelData[S.moveDragStartRow][S.moveDragStartCol] = TILE.EMPTY
    S.levelData[row][col] = oldVal
    local base = GetTileType(oldVal)
    if base == TILE.SPAWN then
        S.spawnCol = col
        S.spawnRow = row
    end
    Undo.RecordTileChange(S.moveDragStartCol, S.moveDragStartRow, oldVal, TILE.EMPTY)
    Undo.RecordTileChange(col, row, TILE.EMPTY, oldVal)
    S.selectedTileCol = col
    S.selectedTileRow = row
    Undo.dirty = true
    Undo.saveTimer = Undo.saveDelay
    local names = { [TILE.SPAWN]="主角", [TILE.FUEL]="火焰", [TILE.GOAL]="终点",
                    [TILE.SPIKE]="刺", [TILE.SWITCH]="开关", [TILE.GATE]="门" }
    S.SetMessage((names[base] or "物体") .. " 移动到 (" .. col .. "," .. row .. ")", 1.5)
end

-- ====================================================================
-- HandleMouseWheel
-- ====================================================================

function M.HandleMouseWheel(wheel)
    if S.editorMode == MODE.PLAY or S.editorMode == MODE.WORLDPLAY then return end
    if S.dialogMode then return end

    local mx, my = GetDesignMouse()

    if S.editorMode == MODE.WORLDMAP then
        WorldMapEditor.HandleMouseWheel(wheel, mx, my)
        return
    end

    -- 侧边栏滚动
    if S.sidebarOpen and mx >= S.screenDesignW - SIDEBAR_W then
        local maxScroll = math.max(0, #S.savedLevels * 22 - (S.screenDesignH - TOPBAR_H - BOTTOMBAR_H - 24))
        S.sidebarScroll = S.sidebarScroll - wheel * 22
        S.sidebarScroll = math.max(0, math.min(S.sidebarScroll, maxScroll))
        return
    end

    -- 缩放（以鼠标为中心）
    local oldZoom = S.zoomLevel
    if wheel > 0 then
        S.zoomLevel = S.zoomLevel * ZOOM_FACTOR
    elseif wheel < 0 then
        S.zoomLevel = S.zoomLevel / ZOOM_FACTOR
    end
    S.zoomLevel = math.max(ZOOM_MIN, math.min(ZOOM_MAX, S.zoomLevel))

    local mapRelX = mx
    local mapRelY = my - TOPBAR_H
    local worldX = (mapRelX + S.cameraX) / oldZoom
    local worldY = (mapRelY + S.cameraY) / oldZoom
    S.cameraX = worldX * S.zoomLevel - mapRelX
    S.cameraY = worldY * S.zoomLevel - mapRelY
end

return M
