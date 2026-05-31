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
-- 进入游戏（正式 gameplay，不走编辑器 PlayMode）
-- ====================================================================

---@param mode "new"|"continue"
local function LaunchGameWithMode(mode)
    MainMenu.Cleanup()
    _GAMEPLAY_DIRECT = true
    _GAMEPLAY_MODE = mode
    require "gameplay.init"
    ---@diagnostic disable-next-line: redundant-parameter
    Start()

    -- 初始化暂停菜单（gameplay 启动后）
    PauseMenu.Init({
        onResume = nil,
        onBackToMenu = function()
            PauseMenu.Cleanup()
            -- gameplay 的 Stop() 会清理 NanoVG
            if Stop then Stop() end
            _GAMEPLAY_DIRECT = nil
            _GAMEPLAY_MODE = nil
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
    local Recovery = require "cloud_recovery"
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
