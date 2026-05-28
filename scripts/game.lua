-- ====================================================================
-- game.lua - 入口路由（默认编辑器模式）
-- ====================================================================
-- 此文件是构建入口的兼容层。
-- 无论构建工具用 game.lua 还是 main.lua 作为 entry，
-- 都会路由到编辑器模式。
--
-- 编辑器内按 P 可试玩关卡（试玩时加载 gameplay.lua 的逻辑）。
--
-- ⚠️ 注意：请勿在此文件中编写游戏逻辑！
--   游戏代码 → scripts/gameplay.lua
--   编辑器代码 → scripts/editor.lua
-- ====================================================================

require "editor"

-- 构建工具要求入口文件有显式 Start()，
-- editor.lua 的 require 已在全局定义了 Start/Stop/Handle* 等函数，
-- 此处无需额外操作。但为通过静态检查，保留空壳声明作为 fallback：
if not Start then
    function Start()
        print("[game.lua] ERROR: editor.lua did not define Start()")
    end
end
