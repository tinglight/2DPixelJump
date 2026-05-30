-- ====================================================================
-- editor.lua - 火焰像素平台跳跃 关卡编辑器（主入口）
-- ====================================================================
--
-- 【工具列表】:
-- 1. 碰撞方块 (SOLID)
-- 2. 主角出生点 (SPAWN)
-- 3. 回复火焰点 (FUEL)
-- 4. 终点门 (GOAL)
-- 5. 刺陷阱 (SPIKE)
-- 6. 开关 (SWITCH) - 带颜色分组
-- 7. 开关控制门 (GATE) - 与同色开关关联
-- 8. 隐藏墙 (HIDDEN_WALL)
-- 9. 光源 (LIGHT)
--
-- 【编辑操作】:
-- 鼠标左键：放置  |  鼠标右键：擦除
-- 滚轮：缩放  |  WASD：移动视窗  |  1~9：选工具  |  G：换组色
-- Q/R/E：选取/绘制/移动模式
-- 拖拽边界边缘：扩展摄像机边界
-- Z：撤销  |  Ctrl+S：保存  |  Ctrl+L：加载
-- P：进入试玩  |  ESC：退出编辑器
--
-- ====================================================================

require "urhox-libs.UI.VirtualControls"
local UI = require("urhox-libs/UI")
local CloudStorage = require "CloudStorage"
local WorldMapEditor = require "WorldMapEditor"
local FogOfWar = require "FogOfWar"
local LevelGenerator = require "LevelGenerator"

-- ====================================================================
-- 内部模块
-- ====================================================================
local C = require "editor.Constants"
local S = require "editor.State"
local MapData = require "editor.MapData"
local Undo = require "editor.UndoSystem"
local Placement = require "editor.Placement"
local Persistence = require "editor.Persistence"
local PlayMode = require "editor.PlayMode"
local FlameRenderer = require "editor.FlameRenderer"
local Dialogs = require "editor.Dialogs"
local Toolbar = require "editor.Toolbar"
local Sidebar = require "editor.Sidebar"
local GridRenderer = require "editor.GridRenderer"
local InputHandler = require "editor.InputHandler"
local CrossLevel = require "editor.CrossLevel"

-- ====================================================================
-- 依赖注入
-- ====================================================================
local sharedDeps = {
    FogOfWar = FogOfWar,
    WorldMapEditor = WorldMapEditor,
    Persistence = Persistence,
    MapData = MapData,
    PlayMode = PlayMode,
    Dialogs = Dialogs,
}

Dialogs.Inject(sharedDeps)
GridRenderer.Inject(sharedDeps)
InputHandler.Inject(sharedDeps)
PlayMode.Inject({
    FogOfWar = FogOfWar,
    CloudStorage = CloudStorage,
    WorldMapEditor = WorldMapEditor,
    LevelGenerator = LevelGenerator,
    cjson = cjson,
})
CrossLevel.Inject({
    CloudStorage = CloudStorage,
    WorldMapEditor = WorldMapEditor,
    cjson = cjson,
})

-- ====================================================================
-- 分辨率计算
-- ====================================================================
local function RecalcLayout()
    S.physW, S.physH = graphics:GetWidth(), graphics:GetHeight()
    S.dpr = graphics:GetDPR()
    S.logicalW = S.physW / S.dpr
    S.logicalH = S.physH / S.dpr
    S.scaleF = math.min(S.logicalW / C.DESIGN_W, S.logicalH / C.DESIGN_H)
    S.screenDesignW = S.logicalW / S.scaleF
    S.screenDesignH = S.logicalH / S.scaleF
end

-- ====================================================================
-- Start / Stop
-- ====================================================================

function Start()
    print("=== Level Editor v2 (Modular) ===")
    RecalcLayout()

    S.vg = nvgCreate(1)
    if not S.vg then print("ERROR: nvgCreate failed"); return end
    if nvgCreateFont(S.vg, "sans", "Fonts/MiSans-Regular.ttf") == -1 then
        print("ERROR: font load failed"); return
    end

    -- 初始化 UI 库（用于 Modal 对话框，支持 IME 和剪贴板）
    -- 禁用 autoEvents.input，编辑器自己处理所有输入事件
    -- 避免 UI 库的 ScriptObject 事件处理器干扰编辑器的全局 HandleMouseDown
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
        autoEvents = { input = false, update = true, render = true },
    })

    -- 必须设置一个 root，否则 UI.Render() 会因 root_ == nil 直接跳过，
    -- 导致 Modal（overlay）无法渲染和接收输入事件
    UI.SetRoot(UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "none",
    })

    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    MapData.InitEmptyMap()
    Toolbar.InitTopBarButtons()

    -- 本地文件加载
    CloudStorage.Init(function(ok, err)
        Persistence.RefreshSavedLevels()
        if ok then
            local count = #S.savedLevels
            S.SetMessage(count > 0 and ("已加载 " .. count .. " 个关卡") or "就绪", 2.0)
        else
            S.SetMessage("加载失败: " .. (err or "未知错误"), 3.0)
        end

        -- 加载全局玩家参数
        CloudStorage.InitPlayerParams(function(ppOk)
            if ppOk then
                local savedParams = CloudStorage.LoadPlayerParams()
                if savedParams then
                    S.playerParams.baseJumpGrids = savedParams.baseJumpGrids or S.playerParams.baseJumpGrids
                    S.playerParams.fallJumpMultiplier = savedParams.fallJumpMultiplier or S.playerParams.fallJumpMultiplier
                    S.playerParams.maxFallGrids = savedParams.maxFallGrids or S.playerParams.maxFallGrids
                    S.playerParams.maxJumpGrids = savedParams.maxJumpGrids ~= nil and savedParams.maxJumpGrids or S.playerParams.maxJumpGrids
                    S.playerParams.defaultLightDiameter = savedParams.defaultLightDiameter or S.playerParams.defaultLightDiameter
                    -- 同步更新输入框显示
                    S.playerParamInputs = {
                        tostring(S.playerParams.baseJumpGrids),
                        tostring(S.playerParams.fallJumpMultiplier),
                        tostring(S.playerParams.maxFallGrids),
                        tostring(S.playerParams.maxJumpGrids),
                        tostring(S.playerParams.defaultLightDiameter),
                    }
                end
            end
        end)

        -- 初始化世界地图编辑器
        CloudStorage.InitWorldMap(function(wmOk)
            WorldMapEditor.Init(S.vg, function(text, duration)
                S.SetMessage(text, duration or 2.0)
            end, function(nodeFile, nodeName)
                WorldMapEditor.Save()
                Persistence.AutoSaveBeforeSwitch()
                Persistence.LoadLevel(nodeFile)
                S.editorMode = C.MODE_EDIT
                S.SetMessage("编辑关卡: " .. (nodeName or nodeFile), 2.0)
            end)
            WorldMapEditor.SetLayout(S.screenDesignW, S.screenDesignH, C.TOPBAR_H, 0, S.sidebarOpen and C.SIDEBAR_W or 0)

            -- 从主菜单进入时，自动进入世界试玩模式
            if S.fromMainMenu then
                PlayMode.StartWorldPlayMode()
            end
        end)
    end)

    -- 注意：IME 文本输入仅在对话框打开时激活，避免全局显示 I-beam 光标
    -- 见 Dialogs.lua 中 Open*Dialog / ConfirmDialog / CancelDialog

    -- 事件订阅
    SubscribeToEvent(S.vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")
    SubscribeToEvent("TextInput", "HandleTextInput")
    SubscribeToEvent("TextEditing", "HandleTextEditing")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("MouseWheel", "HandleMouseWheel")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")

    print("Level Editor ready. P=play test, Ctrl+S=save, Ctrl+L=load")
end

function Stop()
    if S.vg then nvgDelete(S.vg); S.vg = nil end
end

-- ====================================================================
-- 渲染
-- ====================================================================

function HandleNanoVGRender(eventType, eventData)
    if not S.editorActive or not S.vg then return end
    nvgBeginFrame(S.vg, S.logicalW, S.logicalH, S.dpr)
    nvgScale(S.vg, S.scaleF, S.scaleF)

    if S.editorMode == C.MODE_PLAY or S.editorMode == C.MODE_WORLDPLAY then
        -- 试玩模式：4:3 比例 letterbox 居中显示
        local playW = S.playViewW
        local playH = S.playViewH
        -- 计算 4:3 视口在屏幕设计坐标内的适配缩放和偏移
        local fitScale = math.min(S.screenDesignW / playW, S.screenDesignH / playH)
        local scaledW = playW * fitScale
        local scaledH = playH * fitScale
        local offsetX = (S.screenDesignW - scaledW) * 0.5
        local offsetY = (S.screenDesignH - scaledH) * 0.5

        -- 绘制 letterbox 黑边
        nvgBeginPath(S.vg)
        nvgRect(S.vg, 0, 0, S.screenDesignW, S.screenDesignH)
        nvgFillColor(S.vg, nvgRGBA(0, 0, 0, 255))
        nvgFill(S.vg)

        -- 平移到居中位置，缩放到 4:3 视口坐标系
        nvgSave(S.vg)
        nvgTranslate(S.vg, offsetX, offsetY)
        nvgScale(S.vg, fitScale, fitScale)

        -- 应用 cameraZoom 额外缩放
        local zoom = S.playerParams.cameraZoom or 1.0
        if zoom ~= 1.0 then
            nvgScale(S.vg, 1.0 / zoom, 1.0 / zoom)
        end
        PlayMode.Draw()
        nvgRestore(S.vg)
    elseif S.editorMode == C.MODE_WORLDMAP then
        WorldMapEditor.Draw()
        Toolbar.DrawTopBar()
        Sidebar.Draw()
    else
        GridRenderer.Draw()
        Toolbar.DrawToolbar()
        Toolbar.DrawSubmenuPopup()
        Toolbar.DrawTopBar()
        Toolbar.DrawBottomBar()
        Sidebar.Draw()
        Dialogs.Draw()
    end

    nvgEndFrame(S.vg)
end

-- ====================================================================
-- 更新
-- ====================================================================

function HandleUpdate(eventType, eventData)
    if not S.editorActive then return end
    local dt = eventData["TimeStep"]:GetFloat()
    S.editorClock = S.editorClock + dt

    if S.msgTimer > 0 then S.msgTimer = S.msgTimer - dt end
    if S.dialogMode then S.renameBlink = S.renameBlink + dt end

    if S.editorMode == C.MODE_PLAY then
        PlayMode.Update(dt)
        return
    end

    if S.editorMode == C.MODE_WORLDPLAY then
        if S.worldPlayCooldown > 0 then
            S.worldPlayCooldown = S.worldPlayCooldown - dt
        end
        if S.panTransition.active then
            PlayMode.UpdatePanTransition(dt)
        else
            PlayMode.Update(dt)
            if S.play.alive and not S.play.won then
                PlayMode.WorldPlayCheckBoundary()
            end
        end
        return
    end

    if S.editorMode == C.MODE_WORLDMAP then
        local mx = input:GetMousePosition().x / S.dpr / S.scaleF
        local my = input:GetMousePosition().y / S.dpr / S.scaleF
        WorldMapEditor.UpdateMouse(mx, my)
        WorldMapEditor.Update(dt)
        return
    end

    -- 编辑模式
    InputHandler.HandleUpdate(dt)
end

-- ====================================================================
-- 输入事件
-- ====================================================================

function HandleKeyDown(eventType, eventData)
    if not S.editorActive then return end
    local key = eventData["Key"]:GetInt()
    InputHandler.HandleKeyDown(key)
end

function HandleKeyUp(eventType, eventData)
end

function HandleTextInput(eventType, eventData)
    if not S.editorActive then return end
    local text = eventData["Text"]:GetString()
    if text and #text > 0 then
        InputHandler.HandleTextInput(text)
    end
end

function HandleTextEditing(eventType, eventData)
    if not S.editorActive then return end
    local composition = eventData["Composition"]:GetString()
    local cursor = eventData["Cursor"]:GetInt()
    local selectionLength = eventData["SelectionLength"]:GetInt()
    InputHandler.HandleTextEditing(composition, cursor, selectionLength)
end

function HandleMouseDown(eventType, eventData)
    if not S.editorActive then return end
    local button = eventData["Button"]:GetInt()
    local mx = input:GetMousePosition().x / S.dpr / S.scaleF
    local my = input:GetMousePosition().y / S.dpr / S.scaleF
    InputHandler.HandleMouseDown(button, mx, my)
end

function HandleMouseUp(eventType, eventData)
    if not S.editorActive then return end
    local button = eventData["Button"]:GetInt()
    local mx = input:GetMousePosition().x / S.dpr / S.scaleF
    local my = input:GetMousePosition().y / S.dpr / S.scaleF
    InputHandler.HandleMouseUp(button, mx, my)
end

function HandleMouseWheel(eventType, eventData)
    if not S.editorActive then return end
    local wheel = eventData["Wheel"]:GetInt()
    InputHandler.HandleMouseWheel(wheel)
end

function HandleScreenMode(eventType, eventData)
    RecalcLayout()
end
