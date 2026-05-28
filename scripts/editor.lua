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

    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true

    MapData.InitEmptyMap()
    Toolbar.InitTopBarButtons()

    -- 云端加载
    S.SetMessage("正在加载云存档...", 10.0)
    CloudStorage.Init(function(ok, err)
        Persistence.RefreshSavedLevels()
        if ok then
            local count = #S.savedLevels
            S.SetMessage(count > 0 and ("云存档已加载 (" .. count .. " 个关卡)") or "云存档已就绪", 3.0)
        else
            S.SetMessage("云存档加载失败: " .. (err or "未知错误") .. "（可正常编辑，保存时重试）", 3.0)
        end

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
        end)
    end)

    -- 事件订阅
    SubscribeToEvent(S.vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")
    SubscribeToEvent("TextInput", "HandleTextInput")
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
    if not S.vg then return end
    nvgBeginFrame(S.vg, S.logicalW, S.logicalH, S.dpr)
    nvgScale(S.vg, S.scaleF, S.scaleF)

    if S.editorMode == C.MODE_PLAY or S.editorMode == C.MODE_WORLDPLAY then
        PlayMode.Draw()
    elseif S.editorMode == C.MODE_WORLDMAP then
        WorldMapEditor.Draw()
        Toolbar.DrawTopBar()
        Sidebar.Draw()
    else
        GridRenderer.Draw()
        Toolbar.DrawToolbar()
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
    local dt = eventData["TimeStep"]:GetFloat()
    S.editorClock = S.editorClock + dt

    if S.msgTimer > 0 then S.msgTimer = S.msgTimer - dt end
    if S.dialogMode == "rename" then S.renameBlink = S.renameBlink + dt end

    if S.editorMode == C.MODE_PLAY then
        PlayMode.Update(dt)
        return
    end

    if S.editorMode == C.MODE_WORLDPLAY then
        if S.worldPlayCooldown > 0 then
            S.worldPlayCooldown = S.worldPlayCooldown - dt
        end
        PlayMode.Update(dt)
        if S.play.alive and not S.play.won then
            PlayMode.WorldPlayCheckBoundary()
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
    local key = eventData["Key"]:GetInt()
    InputHandler.HandleKeyDown(key)
end

function HandleKeyUp(eventType, eventData)
end

function HandleTextInput(eventType, eventData)
    local text = eventData["Text"]:GetString()
    if text and #text > 0 then
        InputHandler.HandleTextInput(text)
    end
end

function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    local mx = input:GetMousePosition().x / S.dpr / S.scaleF
    local my = input:GetMousePosition().y / S.dpr / S.scaleF
    InputHandler.HandleMouseDown(button, mx, my)
end

function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    local mx = input:GetMousePosition().x / S.dpr / S.scaleF
    local my = input:GetMousePosition().y / S.dpr / S.scaleF
    InputHandler.HandleMouseUp(button, mx, my)
end

function HandleMouseWheel(eventType, eventData)
    local wheel = eventData["Wheel"]:GetInt()
    InputHandler.HandleMouseWheel(wheel)
end

function HandleScreenMode(eventType, eventData)
    RecalcLayout()
end
