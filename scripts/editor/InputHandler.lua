-- ====================================================================
-- editor/InputHandler.lua - 输入事件路由与处理
-- ====================================================================

local C = require "editor.Constants"
local S = require "editor.State"
local TileUtils = require "editor.TileUtils"
local Undo = require "editor.UndoSystem"
local Placement = require "editor.Placement"
local Toolbar = require "editor.Toolbar"
local CloudPanel = require "editor.CloudPanel"

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
local LIGHT_TOOL_INDEX = C.LIGHT_TOOL_INDEX
local LIGHT_ZONE_TOOL_INDEX = C.LIGHT_ZONE_TOOL_INDEX
local UNLIT_LIGHT_TOOL_INDEX = C.UNLIT_LIGHT_TOOL_INDEX
local DECORATION_TOOL_INDEX = C.DECORATION_TOOL_INDEX

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
    S.currentDifficulty = S.currentDifficulty % #diffs + 1
    local diff = diffs[S.currentDifficulty]
    local diffName = C.DIFFICULTY_NAMES[diff] or diff
    S.SetMessage("难度: " .. diffName, 1.5)
end

--- 导出全部数据：将云端缓存直接写入本地 data/ 目录文件
function DoExport()
    local ok, err = pcall(function()
        local CloudStorage = require "CloudStorage"

        -- 导出前先保存当前正在编辑的关卡（避免未保存的关卡丢失）
        if Persistence then
            if S.currentLevelName == "" and S.levelData then
                -- 从未保存过的关卡，先执行"另存为新关卡"
                Persistence.SaveAsNewLevel()
                print("[Export] 自动保存为新关卡")
            elseif S.currentLevelName ~= "" and Undo.dirty then
                -- 有修改未保存的已有关卡
                Persistence.SaveLevel()
                Undo.dirty = false
                print("[Export] 自动保存当前关卡: " .. S.currentLevelName)
            end
        end

        -- 确保目标目录存在（必须先创建目录，否则 File WRITE 会失败）
        fileSystem:CreateDir("data")
        fileSystem:CreateDir("data/levels")

        -- 调试：输出缓存状态
        print("[Export] CloudStorage.IsReady() = " .. tostring(CloudStorage.IsReady()))
        print("[Export] GetNextIndex() = " .. tostring(CloudStorage.GetNextIndex()))

        -- 获取各项数据
        local playerParams = CloudStorage.LoadPlayerParams()
        local worldMap = CloudStorage.LoadWorldMap()
        local nextIndex = CloudStorage.GetNextIndex()
        local levelFiles = CloudStorage.ListLevels()

        print("[Export] ListLevels 返回 " .. #levelFiles .. " 个文件")
        for i, f in ipairs(levelFiles) do
            print("[Export]   " .. i .. ": " .. f)
        end

        -- 如果缓存为空，提示用户先保存
        if #levelFiles == 0 then
            S.SetMessage("没有已保存的关卡，请先保存!", 3.0)
            print("[Export] 缓存为空，请检查：1) 是否已保存过关卡 2) CloudStorage.Init 是否完成")
            return
        end

        -- 写入 data/index.json
        local indexFile = File("data/index.json", FILE_WRITE)
        if indexFile and indexFile:IsOpen() then
            indexFile:WriteString(cjson.encode({ nextIndex = nextIndex }))
            indexFile:Close()
            print("[Export] 写入 data/index.json")
        else
            print("[Export] 无法写入 data/index.json")
        end

        -- 写入 data/player_params.json
        if playerParams then
            local ppFile = File("data/player_params.json", FILE_WRITE)
            if ppFile and ppFile:IsOpen() then
                ppFile:WriteString(cjson.encode(playerParams))
                ppFile:Close()
                print("[Export] 写入 data/player_params.json")
            end
        end

        -- 写入 data/world_map.json
        if worldMap then
            local wmFile = File("data/world_map.json", FILE_WRITE)
            if wmFile and wmFile:IsOpen() then
                wmFile:WriteString(cjson.encode(worldMap))
                wmFile:Close()
                print("[Export] 写入 data/world_map.json")
            end
        end

        -- 写入 data/levels/level_N.json
        local levelCount = 0
        for _, fname in ipairs(levelFiles) do
            local jsonStr = CloudStorage.Load(fname)
            if jsonStr then
                local path = "data/levels/" .. fname
                local lf = File(path, FILE_WRITE)
                if lf and lf:IsOpen() then
                    lf:WriteString(jsonStr)
                    lf:Close()
                    levelCount = levelCount + 1
                else
                    print("[Export] 无法写入 " .. path)
                end
            else
                print("[Export] CloudStorage.Load('" .. fname .. "') 返回 nil")
            end
        end
        print("[Export] 写入 " .. levelCount .. " 个关卡文件到 data/levels/")

        S.SetMessage("已导出 " .. levelCount .. " 个关卡到本地文件!", 3.0)
    end)

    if not ok then
        print("[Export Error] " .. tostring(err))
        S.SetMessage("导出出错: " .. tostring(err), 3.0)
    end
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

    -- 更新工具栏滑动拖拽
    UpdateToolbarDrag()

    -- 更新工具编辑模式拖拽
    UpdateToolEditDrag()

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
    UpdateLightZoneDraw()
    UpdateDecoDrag()
    UpdateDrawErase()
    UpdateAutoSave(dt)
end

-- ====================================================================
-- 工具栏滑动更新
-- ====================================================================
function UpdateToolbarDrag()
    -- pending 阶段：判定是否超阈值转为拖拽
    if S.toolbarDragPending then
        local mx = input:GetMousePosition().x / S.dpr / S.scaleF
        local dx = math.abs(mx - S.toolbarDragStartX)
        if dx > S.toolbarDragThreshold then
            -- 超过阈值 → 转为真正的滑动拖拽
            S.toolbarDragPending = false
            S.toolbarDragPendingSlot = nil
            S.toolbarDragging = true
        end
        return
    end

    if not S.toolbarDragging then return end
    local mx = input:GetMousePosition().x / S.dpr / S.scaleF
    local dx = mx - S.toolbarDragStartX
    local newScroll = S.toolbarDragStartScroll + dx
    -- 边界约束
    local maxScroll = Toolbar.GetToolbarMaxScroll()
    S.toolbarScrollX = math.max(maxScroll, math.min(0, newScroll))
end

-- ====================================================================
-- 工具编辑模式拖拽更新
-- ====================================================================
function UpdateToolEditDrag()
    if not S.toolEditDragging then return end
    local mx = input:GetMousePosition().x / S.dpr / S.scaleF
    S.toolEditDragOffsetX = mx - S.toolEditDragStartX
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
    if key == KEY_ESCAPE then
        print("[InputHandler] HandleKeyDown ESC, editorMode=" .. tostring(S.editorMode) .. " fromMainMenu=" .. tostring(S.fromMainMenu))
    end
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
        print("[InputHandler] ESC in PLAY mode, fromMainMenu=" .. tostring(S.fromMainMenu))
        if S.fromMainMenu then
            -- 正式游戏：ESC 切换暂停菜单
            local PauseMenuMod = require("PauseMenu")
            print("[InputHandler] → calling PauseMenu.Toggle()")
            PauseMenuMod.Toggle()
        else
            -- 编辑器试玩：ESC 返回编辑模式（恢复光源）
            PlayMode.ExitPlayMode()
            S.editorMode = MODE.EDIT
            print("[InputHandler] → returning to MODE_EDIT")
            S.SetMessage("返回编辑模式", 1.5)
        end
    elseif key == KEY_R then
        PlayMode.StartPlayMode()
    end
end

function HandleWorldPlayModeKey(key)
    if key == KEY_ESCAPE then
        print("[InputHandler] ESC in WORLDPLAY mode, fromMainMenu=" .. tostring(S.fromMainMenu))
        if S.fromMainMenu then
            -- 正式游戏：ESC 切换暂停菜单
            local PauseMenuMod = require("PauseMenu")
            print("[InputHandler] → calling PauseMenu.Toggle()")
            PauseMenuMod.Toggle()
        else
            -- 世界地图试玩：ESC 返回世界地图编辑（恢复光源）
            PlayMode.ExitPlayMode()
            S.editorMode = MODE.WORLDMAP
            WorldMapEditor.SetLayout(S.screenDesignW, S.screenDesignH, TOPBAR_H, 0, S.sidebarOpen and SIDEBAR_W or 0)
            print("[InputHandler] → returning to MODE_WORLDMAP")
            S.SetMessage("返回世界地图编辑", 1.5)
        end
    elseif key == KEY_R then
        PlayMode.StartWorldPlayMode()
    end
end

function HandleWorldMapKey(key)
    if key == KEY_ESCAPE then
        -- 世界地图编辑：ESC 返回关卡编辑模式
        S.editorMode = MODE.EDIT
        S.SetMessage("返回编辑模式", 1.5)
        return
    end
    WorldMapEditor.HandleKeyDown(key)
end

function HandleEditorKey(key)
    -- ESC 返回主菜单
    if key == KEY_ESCAPE then
        print("[InputHandler] ESC in EDIT mode → BackToMenu")
        local PauseMenuMod = require("PauseMenu")
        S.editorActive = false
        S.fromMainMenu = false
        PauseMenuMod.BackToMenu()
        return
    end

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

    -- 工具数字键（绑定到槽位，不绑定具体工具）
    if key >= KEY_1 and key <= KEY_9 then
        local slotIdx = key - KEY_1 + 1
        local order = Toolbar.GetToolOrder()
        if slotIdx <= #order then
            local toolIdx = order[slotIdx]
            local prevTool = S.currentTool
            S.currentTool = toolIdx
            S.interactMode = INTERACT.DRAW
            SwitchToHiddenWallTool(toolIdx, prevTool)
        end
        return
    end

    -- 删除键（批量删除框选内容）
    if key == KEY_DELETE then
        DeleteSelection()
        return
    end

    -- Ctrl+C 复制
    if key == KEY_C and input:GetKeyDown(KEY_CTRL) then
        CopySelection()
        return
    end

    -- Ctrl+V 粘贴
    if key == KEY_V and input:GetKeyDown(KEY_CTRL) then
        PasteClipboard()
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

    -- 子菜单弹出层处理（优先级最高）
    if S.submenuOpen and button == MOUSEB_LEFT then
        local hitToolIdx = Toolbar.HitTestSubmenuPopup(mx, my)
        if hitToolIdx then
            -- 选中子菜单中的工具
            S.currentTool = hitToolIdx
            S.interactMode = INTERACT.DRAW
            S.submenuOpen = false
            S.submenuGroupId = nil
            S.ClearSelection()
            return
        end
        -- 点击在弹出层外部 → 关闭子菜单
        if not Toolbar.IsInsideSubmenuPopup(mx, my) then
            S.submenuOpen = false
            S.submenuGroupId = nil
            -- 不 return，继续正常处理（可能点击了工具栏其他位置）
        else
            return  -- 在弹出层内但未命中按钮，吞掉事件
        end
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

    -- 云端同步面板（右下角）
    if button == MOUSEB_LEFT and CloudPanel.HandleMouseDown(mx, my) then
        return
    end

    -- 回收站按钮（底部右下角）
    if button == MOUSEB_LEFT and Toolbar.HitTestTrashButton(mx, my) then
        Dialogs.OpenTrashDialog()
        return
    end

    -- 底部工具栏（barY 与渲染一致：减去状态栏16px）
    local barY = S.screenDesignH - BOTTOMBAR_H - 16
    if my >= barY and my < S.screenDesignH - 16 and button == MOUSEB_LEFT then
        HandleToolbarClick(mx, my, barY)
        return
    end

    -- 编辑模式下，点击非工具区域退出编辑（不保存）
    if S.toolbarEditMode and button == MOUSEB_LEFT then
        S.toolbarEditMode = false
        S.toolOrderPending = nil
        S.toolEditDragging = false
        S.SetMessage("退出编辑(未保存)", 1.5)
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
    -- 将 screenDesign 坐标转换到 4:3 playView 坐标
    local fitScale = math.min(S.screenDesignW / S.playViewW, S.screenDesignH / S.playViewH)
    local offsetX = (S.screenDesignW - S.playViewW * fitScale) * 0.5
    local offsetY = (S.screenDesignH - S.playViewH * fitScale) * 0.5
    local pmx = (mx - offsetX) / fitScale
    local pmy = (my - offsetY) / fitScale

    local backBtnW, backBtnH = 50, 16
    local backBtnX = S.playViewW - backBtnW - 6
    local backBtnY = (22 - backBtnH) * 0.5
    local pad = 6
    if pmx >= backBtnX - pad and pmx < backBtnX + backBtnW + pad and pmy >= backBtnY - pad and pmy < backBtnY + backBtnH + pad then
        PlayMode.ExitPlayMode()
        S.editorMode = MODE.EDIT
        S.SetMessage("返回编辑模式", 1.5)
    end
end

function HandleWorldPlayClick(button, mx, my)
    if button ~= MOUSEB_LEFT then return end
    -- 将 screenDesign 坐标转换到 4:3 playView 坐标
    local fitScale = math.min(S.screenDesignW / S.playViewW, S.screenDesignH / S.playViewH)
    local offsetX = (S.screenDesignW - S.playViewW * fitScale) * 0.5
    local offsetY = (S.screenDesignH - S.playViewH * fitScale) * 0.5
    local pmx = (mx - offsetX) / fitScale
    local pmy = (my - offsetY) / fitScale

    local backBtnW, backBtnH = 60, 16
    local backBtnX = S.playViewW - backBtnW - 6
    local backBtnY = (22 - backBtnH) * 0.5
    local pad = 6
    if pmx >= backBtnX - pad and pmx < backBtnX + backBtnW + pad and pmy >= backBtnY - pad and pmy < backBtnY + backBtnH + pad then
        PlayMode.ExitPlayMode()
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
    elseif id == "bg" then
        Dialogs.OpenBackgroundDialog()
    elseif id == "sidebar" then
        S.sidebarOpen = not S.sidebarOpen
    elseif id == "export" then
        DoExport()
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
    elseif id == "gizmos" then
        S.showGizmos = not S.showGizmos
        S.SetMessage(S.showGizmos and "标记: 显示" or "标记: 隐藏", 1.5)
    elseif id == "random" then
        Persistence.AutoSaveBeforeSwitch()
        PlayMode.GenerateRandomLevel()
    elseif id == "play" then
        Persistence.AutoSaveBeforeSwitch()
        PlayMode.StartPlayMode()
    elseif id == "bg" then
        Dialogs.OpenBackgroundDialog()
    elseif id == "worldmap" then
        Persistence.AutoSaveBeforeSwitch()
        S.editorMode = MODE.WORLDMAP
        WorldMapEditor.SetLayout(S.screenDesignW, S.screenDesignH, TOPBAR_H, 0, S.sidebarOpen and SIDEBAR_W or 0)
        S.SetMessage("世界地图编辑模式", 2.0)
    elseif id == "sidebar" then
        S.sidebarOpen = not S.sidebarOpen
    elseif id == "export" then
        DoExport()
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
    -- 交互模式按钮（非编辑模式时可用）
    if not S.toolbarEditMode then
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
    end

    -- 编辑/确认按钮
    local editHit = Toolbar.HitTestEditButtons(mx, my)
    if editHit == "edit" then
        if not S.toolbarEditMode then
            -- 进入编辑模式：复制当前工具顺序作为临时编辑顺序
            S.toolbarEditMode = true
            local currentOrder = Toolbar.GetToolOrder()
            S.toolOrderPending = {}
            for i, v in ipairs(currentOrder) do
                S.toolOrderPending[i] = v
            end
            S.SetMessage("工具编辑模式: 拖拽调整顺序", 2.0)
        else
            -- 已在编辑模式，点击编辑按钮退出不保存
            S.toolbarEditMode = false
            S.toolOrderPending = nil
            S.toolEditDragging = false
            S.SetMessage("退出编辑(未保存)", 1.5)
        end
        return
    elseif editHit == "confirm" then
        -- 确认保存编辑
        if S.toolbarEditMode and S.toolOrderPending then
            S.toolOrder = {}
            for i, v in ipairs(S.toolOrderPending) do
                S.toolOrder[i] = v
            end
        end
        S.toolbarEditMode = false
        S.toolOrderPending = nil
        S.toolEditDragging = false
        S.SetMessage("工具顺序已保存", 1.5)
        return
    end

    -- 工具栏区域点击
    if Toolbar.HitTestToolbarArea(mx, my) then
        if S.toolbarEditMode then
            -- 编辑模式下：开始拖拽工具（重排）
            local slotIdx = Toolbar.HitTestToolbar(mx, my)
            if slotIdx then
                S.toolEditDragging = true
                S.toolEditDragIndex = slotIdx
                S.toolEditDragStartX = mx
                S.toolEditDragOffsetX = 0
            end
        else
            -- 非编辑模式：进入 pending 状态（等阈值判定是拖拽还是点击）
            S.toolbarDragPending = true
            S.toolbarDragStartX = mx
            S.toolbarDragStartScroll = S.toolbarScrollX
            S.toolbarDragPendingSlot = Toolbar.HitTestToolbar(mx, my) -- 可能为 nil
        end
        return
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

    -- 装饰工具优先处理（无论交互模式），确保拖拽/删除始终可用
    local currentToolDef = C.TOOLS[S.currentTool]
    if currentToolDef and currentToolDef.tile == -3 then
        HandleDecorationToolClick(button, col, row)
        return
    end

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

    -- 无光工具（熄灭灯）
    if S.currentTool == UNLIT_LIGHT_TOOL_INDEX then
        HandleUnlitLightToolClick(button, col, row)
        return
    end

    -- 光域工具
    if S.currentTool == LIGHT_ZONE_TOOL_INDEX then
        HandleLightZoneToolClick(button, col, row)
        return
    end

    -- 装饰工具（tile == -3 的工具都是装饰类型）
    local currentToolDef = C.TOOLS[S.currentTool]
    if currentToolDef and currentToolDef.tile == -3 then
        HandleDecorationToolClick(button, col, row)
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
-- 无光工具（熄灭灯）
-- ====================================================================

function HandleUnlitLightToolClick(button, col, row)
    if button == MOUSEB_LEFT then
        local existIdx = FogOfWar.FindLight(col, row)
        if existIdx then
            -- 已有光源（含熄灭灯），打开参数对话框
            Dialogs.OpenLightDialog(existIdx)
        else
            -- 放置一个熄灭的光源
            local idx = FogOfWar.AddUnlitLight(col, row, 6, 0.5)
            S.selectedLightIndex = idx
            S.lightSources = FogOfWar.GetLightSources()
            Undo.dirty = true
            Undo.saveTimer = Undo.saveDelay
            S.SetMessage("放置无光灯 (" .. col .. "," .. row .. ") 可被火球点亮", 2.0)
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
            S.SetMessage("删除无光灯", 1.5)
        end
    end
end

-- ====================================================================
-- 光域工具
-- ====================================================================

function HandleLightZoneToolClick(button, col, row)
    if button == MOUSEB_LEFT then
        -- 检查是否点击了已有区域（用于选中）
        local zones = FogOfWar.GetLightZones()
        local clickedIdx = 0
        for i, z in ipairs(zones) do
            if col >= z.col1 and col <= z.col2 and row >= z.row1 and row <= z.row2 then
                clickedIdx = i
            end
        end

        if clickedIdx > 0 and not S.lightZoneDrawing then
            -- 选中已有区域
            S.selectedLightZoneIndex = clickedIdx
            S.SetMessage("选中光域 #" .. clickedIdx .. " (右键删除)", 2.0)
        else
            -- 开始框选新区域
            S.lightZoneDrawing = true
            S.lightZoneStartCol = col
            S.lightZoneStartRow = row
            S.lightZoneEndCol = col
            S.lightZoneEndRow = row
            S.selectedLightZoneIndex = 0
        end
    elseif button == MOUSEB_RIGHT then
        -- 右键删除选中区域
        if S.selectedLightZoneIndex > 0 then
            FogOfWar.RemoveLightZone(S.selectedLightZoneIndex)
            S.lightZones = FogOfWar.GetLightZones()
            S.selectedLightZoneIndex = 0
            Undo.dirty = true
            Undo.saveTimer = Undo.saveDelay
            S.SetMessage("删除光域", 1.5)
        end
    end
end

function UpdateLightZoneDraw()
    if not S.lightZoneDrawing then return end
    local mx, my = GetDesignMouse()
    local col, row = ScreenToGrid(mx, my)
    col = math.max(1, math.min(S.MAP_COLS, col))
    row = math.max(1, math.min(S.MAP_ROWS, row))
    S.lightZoneEndCol = col
    S.lightZoneEndRow = row
end

function FinishLightZoneDraw()
    if not S.lightZoneDrawing then return end
    S.lightZoneDrawing = false

    local c1 = math.min(S.lightZoneStartCol, S.lightZoneEndCol)
    local r1 = math.min(S.lightZoneStartRow, S.lightZoneEndRow)
    local c2 = math.max(S.lightZoneStartCol, S.lightZoneEndCol)
    local r2 = math.max(S.lightZoneStartRow, S.lightZoneEndRow)

    -- 至少2x2的区域才创建
    if c2 - c1 < 1 and r2 - r1 < 1 then
        S.SetMessage("区域太小，至少2格", 1.5)
        return
    end

    FogOfWar.AddLightZone(c1, r1, c2, r2)
    S.lightZones = FogOfWar.GetLightZones()
    S.selectedLightZoneIndex = #S.lightZones
    Undo.dirty = true
    Undo.saveTimer = Undo.saveDelay
    S.SetMessage("创建光域 #" .. #S.lightZones .. " (" .. c1 .. "," .. r1 .. ")-(" .. c2 .. "," .. r2 .. ")", 2.0)
end

-- ====================================================================
-- 装饰工具
-- ====================================================================

function HandleDecorationToolClick(button, col, row)
    if button == MOUSEB_LEFT then
        -- 检查是否点击了已有装饰物 → 开始拖拽
        local existIdx = Placement.FindDecoration(col, row)
        if existIdx then
            -- 选中并开始拖拽
            S.selectedDecorationIndex = existIdx
            S.decoDragging = true
            S.decoDragIndex = existIdx
            S.decoDragStartCol = col
            S.decoDragStartRow = row
            S.SetMessage("拖拽装饰物 (松开放置, 双击编辑)", 1.5)
        else
            -- 点击空位 → 打开装饰物配置弹窗
            S.decoDialogCol = col
            S.decoDialogRow = row
            S.decoDialogEditIndex = 0
            S.decoDialogBrightness = 100
            S.decoDialogScale = 100
            S.currentDecorationType = 1
            Dialogs.OpenDecorationDialog()
        end
    elseif button == MOUSEB_RIGHT then
        -- 右键删除
        local existIdx = Placement.FindDecoration(col, row)
        if existIdx then
            table.remove(S.decorations, existIdx)
            if S.selectedDecorationIndex == existIdx then
                S.selectedDecorationIndex = 0
            end
            Undo.dirty = true
            Undo.saveTimer = Undo.saveDelay
            S.SetMessage("删除装饰", 1.5)
        end
    end
end

-- ====================================================================
-- 装饰物拖拽更新（跟随鼠标）
-- ====================================================================

function UpdateDecoDrag()
    if not S.decoDragging then return end
    -- 实时更新装饰物位置，让它跟随鼠标
    local mx, my = GetDesignMouse()
    local col, row = ScreenToGrid(mx, my)
    col = math.max(1, math.min(S.MAP_COLS, col))
    row = math.max(1, math.min(S.MAP_ROWS, row))

    local idx = S.decoDragIndex
    if idx > 0 and idx <= #S.decorations then
        S.decorations[idx].col = col
        S.decorations[idx].row = row
    end
end

-- ====================================================================
-- 装饰物拖拽完成
-- ====================================================================

function FinishDecoDrag(mx, my)
    S.decoDragging = false
    local col, row = ScreenToGrid(mx, my)
    col = math.max(1, math.min(S.MAP_COLS, col))
    row = math.max(1, math.min(S.MAP_ROWS, row))

    local idx = S.decoDragIndex
    if idx > 0 and idx <= #S.decorations then
        local deco = S.decorations[idx]
        -- UpdateDecoDrag 已实时移动位置，这里最终确认
        deco.col = col
        deco.row = row
        if col ~= S.decoDragStartCol or row ~= S.decoDragStartRow then
            -- 真正移动了 → 标记脏
            Undo.dirty = true
            Undo.saveTimer = Undo.saveDelay
            S.SetMessage("装饰已移动到 (" .. col .. "," .. row .. ")", 1.5)
        else
            -- 原地释放 → 打开编辑弹窗
            S.decoDialogCol = deco.col
            S.decoDialogRow = deco.row
            S.decoDialogEditIndex = idx
            S.decoDialogBrightness = deco.brightness or 100
            S.decoDialogScale = deco.scale or 100
            S.currentDecorationType = deco.typeId or 1
            Dialogs.OpenDecorationDialog()
        end
    end
    S.decoDragIndex = 0
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
    -- 装饰物拖拽释放
    if S.decoDragging then
        FinishDecoDrag(mx, my)
        return
    end

    -- 工具栏滑动拖拽释放
    -- pending 状态释放：未超阈值，视为点击
    if S.toolbarDragPending then
        local slotIdx = S.toolbarDragPendingSlot
        S.toolbarDragPending = false
        S.toolbarDragPendingSlot = nil
        if slotIdx then
            local order = Toolbar.GetToolOrder()
            local toolIdx = order[slotIdx]
            if toolIdx then
                local tool = C.TOOLS[toolIdx]
                -- 有子菜单的工具：展开子菜单
                if tool and tool.submenu and C.SUBMENU_GROUPS[tool.submenu] then
                    if S.submenuOpen and S.submenuGroupId == tool.submenu then
                        -- 再次点击同一组 → 关闭
                        S.submenuOpen = false
                        S.submenuGroupId = nil
                    else
                        S.submenuOpen = true
                        S.submenuGroupId = tool.submenu
                        S.submenuSlotIdx = slotIdx
                    end
                else
                    -- 普通工具：直接选中
                    local prevTool = S.currentTool
                    S.currentTool = toolIdx
                    S.interactMode = INTERACT.DRAW
                    SwitchToHiddenWallTool(toolIdx, prevTool)
                    S.ClearSelection()
                    -- 关闭子菜单
                    S.submenuOpen = false
                    S.submenuGroupId = nil
                end
            end
        end
        return
    end

    if S.toolbarDragging then
        S.toolbarDragging = false
        -- 确保边界约束
        local maxScroll = Toolbar.GetToolbarMaxScroll()
        S.toolbarScrollX = math.max(maxScroll, math.min(0, S.toolbarScrollX))
        return
    end

    -- 编辑模式下工具拖拽释放（执行重排）
    if S.toolEditDragging then
        FinishToolEditDrag(mx)
        return
    end

    if S.lightZoneDrawing then
        FinishLightZoneDraw()
        return
    end

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
-- 工具编辑模式拖拽完成：交换位置
-- ====================================================================
function FinishToolEditDrag(mx)
    if not S.toolOrderPending then
        S.toolEditDragging = false
        return
    end

    local btnW = Toolbar.TOOL_BTN_W
    local btnPad = Toolbar.TOOL_BTN_PAD
    local areaStartX = Toolbar.GetToolbarStartX()
    local scrollX = S.toolbarScrollX
    local dragIdx = S.toolEditDragIndex

    -- 计算目标槽位
    local relX = mx - areaStartX - scrollX
    local targetSlot = math.floor(relX / (btnW + btnPad)) + 1
    targetSlot = math.max(1, math.min(#S.toolOrderPending, targetSlot))

    -- 执行位置交换（移动而非简单交换）
    if targetSlot ~= dragIdx then
        local item = table.remove(S.toolOrderPending, dragIdx)
        table.insert(S.toolOrderPending, targetSlot, item)
    end

    S.toolEditDragging = false
    S.toolEditDragIndex = 0
    S.toolEditDragOffsetX = 0
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
    -- 也收集范围内的装饰物
    for i, deco in ipairs(S.decorations) do
        if deco.col >= c1 and deco.col <= c2 and deco.row >= r1 and deco.row <= r2 then
            local entry = { col = deco.col, row = deco.row, isLight = false, lightIdx = 0, isDecoration = true, decoIdx = i }
            if toolTile == -3 then
                priorityList[#priorityList + 1] = entry
            else
                otherList[#otherList + 1] = entry
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
    elseif Placement.FindDecoration(col, row) then
        -- 选中装饰物
        local decoIdx = Placement.FindDecoration(col, row)
        S.selectedTileCol = col
        S.selectedTileRow = row
        S.selectedIsLight = false
        S.selectedTiles = {{ col = col, row = row, isLight = false, lightIdx = 0, isDecoration = true, decoIdx = decoIdx }}
        local deco = S.decorations[decoIdx]
        local decoType = C.DECORATION_TYPES[deco.typeId] or { name = "装饰" }
        S.SetMessage("选中: " .. decoType.name .. " (" .. col .. "," .. row .. ")", 1.5)
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

-- ====================================================================
-- 批量删除
-- ====================================================================

function DeleteSelection()
    if #S.selectedTiles == 0 then
        S.SetMessage("没有选中内容", 1.0)
        return
    end

    local deltas = {}
    local lightRemoveCount = 0
    local decoRemoveCount = 0

    -- 收集要删除的装饰物索引（需要从大到小删除以避免索引错乱）
    local decoIndicesToRemove = {}

    for _, st in ipairs(S.selectedTiles) do
        if st.isLight then
            -- 删除光源
            local removed = FogOfWar.RemoveLight(st.col, st.row)
            if removed then
                lightRemoveCount = lightRemoveCount + 1
            end
        elseif st.isDecoration then
            -- 收集装饰物索引
            local decoIdx = Placement.FindDecoration(st.col, st.row)
            if decoIdx then
                decoIndicesToRemove[#decoIndicesToRemove + 1] = decoIdx
            end
        else
            -- 删除地块（不删除 SPAWN）
            local oldVal = S.levelData[st.row][st.col]
            if oldVal ~= TILE.EMPTY and oldVal ~= TILE.SPAWN then
                S.levelData[st.row][st.col] = TILE.EMPTY
                deltas[#deltas + 1] = {
                    col = st.col, row = st.row,
                    oldVal = oldVal, newVal = TILE.EMPTY,
                }
            end
        end
    end

    -- 从大到小排序后删除装饰物，避免索引错乱
    table.sort(decoIndicesToRemove, function(a, b) return a > b end)
    for _, idx in ipairs(decoIndicesToRemove) do
        table.remove(S.decorations, idx)
        decoRemoveCount = decoRemoveCount + 1
    end

    -- 记录到撤销栈（单次撤销）
    if #deltas > 0 then
        Undo.RecordBatch(deltas, "delete")
    end
    if lightRemoveCount > 0 then
        S.lightSources = FogOfWar.GetLightSources()
        Undo.dirty = true
        Undo.saveTimer = Undo.saveDelay
    end
    if decoRemoveCount > 0 then
        Undo.dirty = true
        Undo.saveTimer = Undo.saveDelay
    end

    local total = #deltas + lightRemoveCount + decoRemoveCount
    S.SetMessage("已删除 " .. total .. " 个物体", 1.5)
    S.ClearSelection()
end

-- ====================================================================
-- 复制
-- ====================================================================

function CopySelection()
    if #S.selectedTiles == 0 then
        S.SetMessage("没有选中内容", 1.0)
        return
    end

    -- 计算选区左上角作为锚点
    local minCol, minRow = math.huge, math.huge
    for _, st in ipairs(S.selectedTiles) do
        if st.col < minCol then minCol = st.col end
        if st.row < minRow then minRow = st.row end
    end

    local clipTiles = {}
    local clipLights = {}

    for _, st in ipairs(S.selectedTiles) do
        local colOff = st.col - minCol
        local rowOff = st.row - minRow
        if st.isLight then
            local light = FogOfWar.GetLight(st.lightIdx)
            if light then
                clipLights[#clipLights + 1] = {
                    colOffset = colOff,
                    rowOffset = rowOff,
                    diameter = light.diameter,
                    feather = light.feather,
                }
            end
        else
            local val = S.levelData[st.row][st.col]
            if val ~= TILE.EMPTY and val ~= TILE.SPAWN then
                clipTiles[#clipTiles + 1] = {
                    colOffset = colOff,
                    rowOffset = rowOff,
                    value = val,
                }
            end
        end
    end

    if #clipTiles == 0 and #clipLights == 0 then
        S.SetMessage("没有可复制的内容", 1.0)
        return
    end

    S.clipboard = { tiles = clipTiles, lights = clipLights }
    S.SetMessage("已复制 " .. (#clipTiles + #clipLights) .. " 个物体", 1.5)
end

-- ====================================================================
-- 粘贴
-- ====================================================================

function PasteClipboard()
    if not S.clipboard then
        S.SetMessage("剪贴板为空", 1.0)
        return
    end

    -- 粘贴到当前鼠标所在格子位置
    local mx, my = GetDesignMouse()
    local baseCol, baseRow = ScreenToGrid(mx, my)
    baseCol = math.max(1, math.min(S.MAP_COLS, baseCol))
    baseRow = math.max(1, math.min(S.MAP_ROWS, baseRow))

    local deltas = {}
    local pastedCount = 0

    -- 粘贴地块
    for _, ct in ipairs(S.clipboard.tiles) do
        local col = baseCol + ct.colOffset
        local row = baseRow + ct.rowOffset
        if col >= 1 and col <= S.MAP_COLS and row >= 1 and row <= S.MAP_ROWS then
            local oldVal = S.levelData[row][col]
            if oldVal == TILE.EMPTY then
                S.levelData[row][col] = ct.value
                deltas[#deltas + 1] = {
                    col = col, row = row,
                    oldVal = oldVal, newVal = ct.value,
                }
                pastedCount = pastedCount + 1
            end
        end
    end

    -- 粘贴光源
    local lightPastedCount = 0
    for _, cl in ipairs(S.clipboard.lights) do
        local col = baseCol + cl.colOffset
        local row = baseRow + cl.rowOffset
        if col >= 1 and col <= S.MAP_COLS and row >= 1 and row <= S.MAP_ROWS then
            -- 避免重复放置光源
            if not FogOfWar.FindLight(col, row) then
                FogOfWar.AddLight(col, row, cl.diameter, cl.feather)
                lightPastedCount = lightPastedCount + 1
            end
        end
    end

    -- 记录到撤销栈
    if #deltas > 0 then
        Undo.RecordBatch(deltas, "paste")
    end
    if lightPastedCount > 0 then
        S.lightSources = FogOfWar.GetLightSources()
        Undo.dirty = true
        Undo.saveTimer = Undo.saveDelay
    end

    local total = pastedCount + lightPastedCount
    if total > 0 then
        S.SetMessage("已粘贴 " .. total .. " 个物体", 1.5)
    else
        S.SetMessage("粘贴失败: 目标位置被占用", 1.5)
    end
end

return M
