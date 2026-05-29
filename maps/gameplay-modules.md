# Gameplay 模块架构索引

> 版本: 1.2.0  
> 重构日期: 2026-05-30  
> 原始文件: `scripts/gameplay.lua` (2049行) → 拆分为 8 个独立模块

---

## 目录结构

```
scripts/
├── gameplay.lua              # 兼容层（仅 require gameplay.init）
├── gameplay/
│   ├── init.lua              # 主入口：模块编排、事件绑定、游戏循环
│   ├── Config.lua            # 常量定义、角色配置、火焰形状、颜色
│   ├── PixelSystem.lua       # 像素状态管理（初始化、剥离、恢复）
│   ├── Physics.lua           # 碰撞检测、地形判定
│   ├── LevelManager.lua      # 关卡加载、世界地图切换、过渡动画
│   ├── PlayerController.lua  # 玩家逻辑（移动、跳跃、垂直物理、收集）
│   ├── Animation.lua         # 表现层动画（火焰帧、灯笼晃动、粒子、压缩）
│   └── Renderer.lua          # 渲染系统（背景、网格、地图、角色、HUD）
├── LevelGenerator.lua        # 关卡随机生成器（未修改）
├── CloudStorage.lua          # 云存储接口（未修改）
├── version.lua               # 版本号
├── main.lua                  # 入口路由
└── editor/                   # 编辑器模块（未修改）
```

---

## 模块职责与接口

### Config.lua
**职责**: 集中管理所有游戏常量和配置参数

| 导出 | 类型 | 说明 |
|------|------|------|
| `M.GRID` | number | 每格像素数 (16) |
| `M.DESIGN_W/H` | number | 设计分辨率 (480×272) |
| `M.MAP_COLS/ROWS` | number | 地图尺寸 (60×17) |
| `M.STATE_PLAYING/GAMEOVER/WIN` | number | 游戏状态枚举 |
| `M.PLAYER_CONFIG` | table | 角色完整配置 |
| `M.levelPlayerParams` | table | 关卡级玩家参数 |
| `M.CHAR_SHAPE` | table | 10×10 火焰像素点阵 |
| `M.FLAME_COLORS` | table | 每行火焰颜色 |
| `M.GROUP_COLORS` | table | 开关/门颜色组 |

**依赖**: 无

---

### PixelSystem.lua
**职责**: 管理火焰角色的像素生死状态

| 导出 | 类型 | 说明 |
|------|------|------|
| `M.pixelState` | table | 二维像素状态数组 |
| `M.totalPixels` | number | 总像素数 |
| `M.alivePixels` | number | 存活像素数 |
| `M.Init()` | function | 初始化/重建像素状态 |
| `M.StripPixels(n)` | function | 从外向内剥离 n 个像素 |
| `M.RecoverPixels(n)` | function | 从内向外恢复 n 个像素 |

**依赖**: Config

---

### Physics.lua
**职责**: 提供碰撞检测和地形查询

| 导出 | 类型 | 说明 |
|------|------|------|
| `M.Inject(deps)` | function | 注入 levelData/switchState/TILE |
| `M.SetLevelData(data)` | function | 更新关卡数据引用 |
| `M.GetTileType(value)` | function | 解码地块值 → base, group |
| `M.IsSolid(col, row)` | function | 是否为实体格 |
| `M.IsPlatform(col, row)` | function | 是否为平台格 |
| `M.PlayerGridSize()` | function | 玩家占据的格子数 |
| `M.PlayerCollidesAt(gx, gy)` | function | 指定位置碰撞测试 |
| `M.PlayerOnGround(gx, gy)` | function | 地面接触检测 |

**依赖**: Config，运行时通过 Inject 获取 levelData/switchState/TILE

---

### LevelManager.lua
**职责**: 关卡生命周期管理、世界地图连通切换

| 导出 | 类型 | 说明 |
|------|------|------|
| `M.Inject(deps)` | function | 注入 LevelGenerator/CloudStorage/PixelSystem/Physics |
| `M.levelData` | table | 当前关卡地图数据 |
| `M.worldMapData` | table | 世界地图连通数据 |
| `M.transition` | table | 过渡动画状态 |
| `M.InitLevel(player)` | function | 随机生成关卡 |
| `M.LoadLevelFromFile(filename, player)` | function | 从云存储加载关卡 |
| `M.FindConnectedLevel(direction)` | function | 查找方向连通关卡 |
| `M.StartLevelTransition(file, dir)` | function | 启动过渡动画 |
| `M.UpdateTransition(dt, player, cameraState)` | function | 更新过渡 |
| `M.CheckBoundaryTransition(player)` | function | 边界切换检测 |
| `M.ResetCollectibles()` | function | 重置收集品 |

**依赖**: Config, Physics, PixelSystem (通过 Inject)

---

### PlayerController.lua
**职责**: 玩家状态、移动逻辑、跳跃力学、物品收集

| 导出 | 类型 | 说明 |
|------|------|------|
| `M.Inject(deps)` | function | 注入 Physics/PixelSystem/LevelManager/Animation |
| `M.player` | table | 玩家完整状态 |
| `M.ResetPlayer()` | function | 重置玩家状态 |
| `M.CalcJumpHeight()` | function | 计算当前跳跃高度 |
| `M.PlayerJump()` | function | 执行跳跃 |
| `M.PlayerMoveOneGrid(dir)` | function | 水平移动一格 |
| `M.UpdateVertical(dt)` | function | 垂直物理更新 → "gameover"/nil |
| `M.CheckItemCollection()` | function | 物品收集检测 → "gameover"/"win"/nil |

**依赖**: Config, Physics, PixelSystem, LevelManager, Animation (通过 Inject)

---

### Animation.lua
**职责**: 所有表现层动画系统

| 导出 | 类型 | 说明 |
|------|------|------|
| `M.Inject(deps)` | function | 注入 Physics/PixelSystem/PlayerController |
| `M.rowOffsets` | table | 每行水平偏移 |
| `M.lanternRowShifts` | table | 灯笼晃动偏移 |
| `M.fallParticles` | table | 下落粒子列表 |
| `M.jumpSquash` | table | 跳跃压缩状态 |
| `M.cantJumpShake` | table | 抖动状态 |
| `M.Update(dt, gameTime)` | function | 统一动画更新入口 |
| `M.Reset()` | function | 重置所有动画状态 |
| `M.TriggerJumpSquash()` | function | 触发跳跃压缩 |
| `M.TriggerCantJumpShake()` | function | 触发抖动 |
| `M.GetJumpSquashForPixel(row, col)` | function | 获取像素形变 |
| `M.GetCantJumpShakeOffset()` | function | 获取抖动偏移 |

**依赖**: Config, Physics, PixelSystem, PlayerController (通过 Inject)

---

### Renderer.lua
**职责**: 所有 NanoVG 渲染（背景、网格、地图、火焰角色、HUD）

| 导出 | 类型 | 说明 |
|------|------|------|
| `M.Inject(deps)` | function | 注入所有数据源模块 |
| `M.SetContext(ctx)` | function | 每帧设置渲染上下文 |
| `M.DrawBackground()` | function | 绘制渐变背景 |
| `M.DrawGrid()` | function | 绘制格子网格 |
| `M.DrawMap()` | function | 绘制地图地块 |
| `M.DrawPlayer()` | function | 绘制火焰角色 |
| `M.DrawFallParticles()` | function | 绘制下落粒子 |
| `M.DrawHUD()` | function | 绘制顶部状态栏 |
| `M.DrawLevelTransition()` | function | 绘制过渡遮罩 |

**依赖**: Config, Physics, PixelSystem, PlayerController, LevelManager, Animation (通过 Inject)

---

### init.lua
**职责**: 模块编排、依赖注入、引擎事件绑定、游戏主循环

| 全局函数 | 说明 |
|----------|------|
| `Start()` | 初始化 NanoVG、关卡、控件、事件订阅 |
| `Stop()` | 释放 NanoVG |
| `HandleNanoVGRender()` | 渲染帧 |
| `HandleUpdate()` | 逻辑帧（输入、物理、动画） |
| `HandleKeyDown()` | 键盘事件 |
| `HandleScreenMode()` | 分辨率变化 |

**依赖**: 所有子模块 + LevelGenerator + CloudStorage + VirtualControls

---

## 依赖关系图

```
                    ┌─────────────┐
                    │  init.lua   │ ← 引擎事件入口
                    └──────┬──────┘
                           │ 编排 & 注入
            ┌──────────────┼──────────────┐
            │              │              │
    ┌───────▼──────┐ ┌────▼────┐ ┌───────▼──────┐
    │PlayerController│ │Animation│ │   Renderer   │
    └───────┬──────┘ └────┬────┘ └───────┬──────┘
            │              │              │
    ┌───────▼──────┐       │       ┌──────▼──────┐
    │   Physics    │◄──────┤       │LevelManager │
    └───────┬──────┘       │       └──────┬──────┘
            │              │              │
    ┌───────▼──────┐ ┌────▼────┐         │
    │  PixelSystem │ │  Config  │◄────────┘
    └──────────────┘ └─────────┘
```

---

## 设计原则

1. **依赖注入 (DI)**: 模块间通过 `Inject(deps)` 传递引用，避免硬耦合
2. **单一职责**: 每个模块只负责一个功能域
3. **数据流清晰**: Config → Physics/PixelSystem → PlayerController/Animation → Renderer
4. **向后兼容**: `gameplay.lua` 保留为兼容入口，仅一行 require
5. **可测试性**: 模块可单独加载和注入 mock 依赖
