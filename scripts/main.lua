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
local MainMenu = require "MainMenu"
local PauseMenu = require "PauseMenu"

-- ====================================================================
-- 前向声明
-- ====================================================================
local LaunchGame, LaunchEditor

-- ====================================================================
-- 切换到编辑器/游戏模式
-- ====================================================================
LaunchGame = function()
    MainMenu.Cleanup()
    require "editor"
    local S = require "editor.State"
    S.fromMainMenu = true
    ---@diagnostic disable-next-line: redundant-parameter
    Start()

    -- 初始化暂停菜单（编辑器启动后）
    PauseMenu.Init({
        onResume = nil,
        onBackToMenu = function()
            PauseMenu.Cleanup()
            S.fromMainMenu = false
            MainMenu.Init({
                onStartGame = LaunchGame,
                onContinue = LaunchGame,
                onOpenEditor = LaunchEditor, ---@diagnostic disable-line: undefined-global
            })
        end,
        onOpenEditor = function()
            PauseMenu.Cleanup()
            S.fromMainMenu = false
        end,
    })
end

LaunchEditor = function()
    MainMenu.Cleanup()
    require "editor"
    local S = require "editor.State"
    S.fromMainMenu = false
    ---@diagnostic disable-next-line: redundant-parameter
    Start()
end

-- ====================================================================
-- 引擎入口（主菜单）
-- ====================================================================
function Start()
    SampleStart()
    SampleInitMouseMode(MM_FREE)

    MainMenu.Init({
        onStartGame = LaunchGame,
        onContinue = LaunchGame,
        onOpenEditor = LaunchEditor,
    })

    print("[main.lua] Main menu initialized")
end

function Stop()
    MainMenu.Cleanup()
end
