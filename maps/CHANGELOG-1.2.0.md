# 变更日志 v1.2.0 — Gameplay 模块化重构

**日期**: 2026-05-30  
**类型**: 重构 (refactor)  
**影响范围**: gameplay 系统全量代码

---

## 概述

将单体文件 `scripts/gameplay.lua`（2049行）拆分为 8 个职责单一的独立模块，
采用依赖注入模式解耦模块间引用，保持功能完全向后兼容。

---

## 变更清单

### 新增文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `scripts/gameplay/Config.lua` | ~120 | 游戏常量、角色配置、火焰形状/颜色 |
| `scripts/gameplay/PixelSystem.lua` | ~70 | 像素状态（初始化/剥离/恢复） |
| `scripts/gameplay/Physics.lua` | ~100 | 碰撞检测、地形判定 |
| `scripts/gameplay/LevelManager.lua` | ~260 | 关卡加载、世界地图切换、过渡动画 |
| `scripts/gameplay/PlayerController.lua` | ~250 | 玩家逻辑（移动/跳跃/物理/收集） |
| `scripts/gameplay/Animation.lua` | ~280 | 表现层动画全系统 |
| `scripts/gameplay/Renderer.lua` | ~400 | NanoVG 渲染全系统 |
| `scripts/gameplay/init.lua` | ~310 | 模块编排、事件绑定、游戏循环 |
| `maps/gameplay-modules.md` | - | 模块架构索引文档 |
| `maps/CHANGELOG-1.2.0.md` | - | 本变更日志 |

### 修改文件

| 文件 | 变更说明 |
|------|---------|
| `scripts/gameplay.lua` | 2049行 → 9行兼容层（仅 require gameplay.init） |
| `scripts/version.lua` | "1.1.4" → "1.2.0" |
| `.project/project.json` | version "1.1.3" → "1.2.0" |

### 未修改文件

- `scripts/LevelGenerator.lua` — 关卡生成器，接口不变
- `scripts/CloudStorage.lua` — 云存储接口，不变
- `scripts/main.lua` — 入口路由，不变
- `scripts/game.lua` — 兼容入口，不变
- `scripts/editor/` — 编辑器全部模块，不变

---

## 架构设计决策

### 1. 依赖注入模式

```lua
-- 模块声明依赖接口
function M.Inject(deps)
    Physics = deps.Physics
    PixelSystem = deps.PixelSystem
end

-- init.lua 统一注入
PlayerController.Inject({
    Physics = Physics,
    PixelSystem = PixelSystem,
    LevelManager = LevelManager,
    Animation = Animation,
})
```

**优势**:
- 模块可独立加载和测试
- 依赖关系显式可见
- 避免 Lua require 循环引用

### 2. 向后兼容

原始 `gameplay.lua` 保留为一行 require 兼容层，确保：
- 编辑器 PlayMode 的 `require "gameplay"` 继续工作
- 任何外部引用不受影响

### 3. 状态管理策略

| 状态类型 | 存放位置 | 访问方式 |
|---------|---------|---------|
| 游戏常量 | Config.lua | 直接 require |
| 像素状态 | PixelSystem.M.* | 模块级字段 |
| 关卡数据 | LevelManager.levelData | 模块级字段 |
| 玩家状态 | PlayerController.player | 模块级 table |
| 动画状态 | Animation.M.* | 模块级字段 |
| 帧级上下文 | init.lua 局部变量 | 通过 SetContext/参数传递 |

### 4. 模块间通信模式

- **数据查询**: 直接引用模块字段 (如 `PixelSystem.alivePixels`)
- **行为触发**: 调用模块函数 (如 `Animation.TriggerJumpSquash()`)
- **状态更新通知**: 通过 Set* 函数 (如 `Physics.SetLevelData(data)`)
- **回调**: 通过 SetCallbacks 注册 (如 `LevelManager.SetCallbacks({recalcLayout=...})`)

---

## 代码行数统计

| 指标 | 重构前 | 重构后 |
|------|-------|-------|
| gameplay.lua | 2049 行 | 9 行 (兼容层) |
| 总 gameplay 代码 | 2049 行 | ~1790 行 (8个模块合计) |
| 最大单文件 | 2049 行 | ~400 行 (Renderer) |
| 模块数 | 1 | 8 |

**注**: 总行数略有减少是因为去除了重复的分隔注释和空行。

---

## 测试要点

- [x] 游戏启动正常（Start 函数执行无错误）
- [x] 火焰角色渲染正确
- [x] 移动/跳跃操作响应正常
- [x] 像素剥离/恢复机制工作
- [x] 关卡加载和切换功能正常
- [x] 世界地图过渡动画正常
- [x] 虚拟控件（摇杆/跳跃按钮）工作
- [x] HUD 显示正确

---

## 版本号变更理由

`1.1.4` → `1.2.0`

根据语义化版本规范 (SemVer):
- **MINOR** (中版本号) 递增: 重构引入了新的模块化架构，向后兼容
- **PATCH** 归零: 随 MINOR 版本递增
- 无 MAJOR 变更: 公开接口（全局 Start/Stop/Handle* 函数）未变
