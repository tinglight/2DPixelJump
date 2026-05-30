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

-- ====================================================================
-- 切换到编辑器/游戏模式
-- require "editor" 会定义全局 Start/Stop/HandleUpdate 等函数，
-- 我们保存自己的 Start 引用后再 require，然后调用 editor 的 Start
-- ====================================================================
local function LaunchEditor()
    MainMenu.Cleanup()
    -- require editor（它会覆盖全局 Start 等函数）
    require "editor"
    -- editor 的 Start 现在是全局的，直接调用
    ---@diagnostic disable-next-line: redundant-parameter
    Start()
end

-- ====================================================================
-- 引擎入口（主菜单）
-- ====================================================================
function Start()
    SampleStart()
    SampleInitMouseMode(MM_FREE)

    -- 显示主菜单
    MainMenu.Init({
        onStartGame = LaunchEditor,
        onContinue = LaunchEditor,
        onOpenEditor = LaunchEditor,
    })

    print("[main.lua] Main menu initialized")
end

function Stop()
    MainMenu.Cleanup()
end
