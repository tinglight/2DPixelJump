-- ====================================================================
-- main.lua - 入口路由（主菜单 → 编辑器/游戏）
-- ====================================================================
-- 启动后进入主菜单界面。
-- 主菜单提供：开始游戏、继续游戏、设置、退出、编辑器入口。
--
-- ⚠️ 注意：请勿在此文件中编写游戏逻辑！
--   主菜单代码 → scripts/MainMenu.lua
--   游戏代码 → scripts/gameplay/init.lua
--   编辑器代码 → scripts/editor.lua
-- ====================================================================

require "LuaScripts/Utilities/Sample"
local MainMenu = require "ui.MainMenu"
local PauseMenu = require "ui.PauseMenu"
local LoadingScreen = require "ui.LoadingScreen"

-- ====================================================================
-- 前向声明
-- ====================================================================
local LaunchGame, LaunchEditor

-- ====================================================================
-- 进入游戏（复用编辑器的世界试玩模式 MODE_WORLDPLAY）
-- ====================================================================

---@param mode "new"|"continue"
local function LaunchGameWithMode(mode)
    MainMenu.Cleanup()

    -- 显示 Loading 界面（在编辑器初始化前激活，遮盖闪烁）
    LoadingScreen.Show()

    -- 加载编辑器模块，设置 fromMainMenu 标志
    require "editor"
    local S = require "editor.State"
    S.fromMainMenu = true
    S.editorActive = true
    ---@diagnostic disable-next-line: redundant-parameter
    Start()

    -- 初始化暂停菜单（编辑器世界试玩模式下 ESC 弹出暂停菜单）
    PauseMenu.Init({
        onResume = nil,
        onBackToMenu = function()
            PauseMenu.Cleanup()
            S.editorActive = false
            S.fromMainMenu = false
            if Stop then Stop() end
            MainMenu.Init({
                onStartGame = LaunchGame,
                onContinue = function() LaunchGameWithMode("continue") end,
                onOpenEditor = LaunchEditor, ---@diagnostic disable-line: undefined-global
            })
        end,
        onOpenEditor = nil,
    })
end

LaunchGame = function()
    LaunchGameWithMode("new")
end

LaunchEditor = function()
    MainMenu.Cleanup()
    require "editor"
    local S = require "editor.State"
    S.fromMainMenu = false
    S.editorActive = true
    ---@diagnostic disable-next-line: redundant-parameter
    Start()

    -- 也初始化暂停菜单（确保 ESC 可以返回主菜单）
    PauseMenu.Init({
        onResume = nil,
        onBackToMenu = function()
            PauseMenu.Cleanup()
            S.editorActive = false
            S.fromMainMenu = false
            MainMenu.Init({
                onStartGame = LaunchGame,
                onContinue = function() LaunchGameWithMode("continue") end,
                onOpenEditor = LaunchEditor,
            })
        end,
        onOpenEditor = function()
            PauseMenu.Close()
        end,
    })
end

-- ====================================================================
-- 引擎入口（主菜单）
-- ====================================================================
function Start()
    SampleStart()
    SampleInitMouseMode(MM_FREE)

    -- [临时] 云端关卡数据恢复诊断
    local Recovery = require "cloud.cloud_recovery"
    Recovery.RestoreAll()

    MainMenu.Init({
        onStartGame = LaunchGame,
        onContinue = function() LaunchGameWithMode("continue") end,
        onOpenEditor = LaunchEditor,
    })

    print("[main.lua] Main menu initialized")
end

function Stop()
    MainMenu.Cleanup()
end
