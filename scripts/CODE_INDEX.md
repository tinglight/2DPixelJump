# 代码索引 (Code Index)

> 供 AI Agent 快速定位代码模块、理解依赖关系、高效导航项目结构。
>
> 总计：59 个 Lua 文件，约 29,855 行代码

---

## 目录结构总览

```
scripts/
├── main.lua                    # 入口：路由到 MainMenu / Editor / Game
├── editor.lua                  # 编辑器入口（事件注册、渲染循环）
├── game.lua                    # 游戏入口（委托 gameplay/init）
├── gameplay.lua                # gameplay 包入口（委托 gameplay/init）
├── version.lua                 # 版本号常量
│
├── cloud/                      # ☁️ 云存储系统
│   ├── CloudStorage.lua        # 云端关卡存储、垃圾箱、备份、玩家参数
│   └── cloud_recovery.lua      # 云端数据恢复工具
│
├── rendering/                  # 🎨 渲染系统（NanoVG 绘制）
│   ├── SolidRenderer.lua       # 实心方块渲染（砖/柱/下水道/水面）
│   ├── FogOfWar.lua            # 战争迷雾/光照系统
│   └── CurtainRenderer.lua     # 窗帘/藤蔓渲染
│
├── ui/                         # 🖼️ UI 界面
│   ├── MainMenu.lua            # 主菜单
│   └── PauseMenu.lua           # 暂停菜单
│
├── level/                      # 🗺️ 关卡系统
│   ├── LevelGenerator.lua      # 程序化关卡生成
│   └── WorldMapEditor.lua      # 世界地图编辑器
│
├── editor/                     # ✏️ 编辑器系统
│   ├── Constants.lua           # 常量定义（格子、模式、工具）
│   ├── State.lua               # 编辑器全局状态
│   ├── InputHandler.lua        # 输入处理（键盘/鼠标分发）
│   ├── PlayMode.lua            # 试玩模式协调器
│   ├── Toolbar.lua             # 顶栏/底栏/工具栏 UI
│   ├── Sidebar.lua             # 侧边栏（关卡列表）
│   ├── Dialogs.lua             # 对话框系统
│   ├── GridRenderer.lua        # 网格/瓦片渲染
│   ├── FlameRenderer.lua       # 火焰动画渲染
│   ├── PipeSystem.lua          # 管道系统（水流/碰撞）
│   ├── Placement.lua           # 瓦片放置逻辑
│   ├── TileUtils.lua           # 瓦片工具函数
│   ├── MapData.lua             # 地图数据（初始化/调整尺寸）
│   ├── Persistence.lua         # 关卡持久化（保存/加载/自动保存）
│   ├── LevelFileIO.lua         # 文件 I/O（导入/导出）
│   ├── UndoSystem.lua          # 撤销系统
│   ├── CrossLevel.lua          # 跨关卡投射物
│   ├── CloudPanel.lua          # 云存储面板 UI
│   ├── GMTool.lua              # GM 调试工具
│   └── play/                   # 试玩模式子模块
│       ├── Physics.lua         # 碰撞检测
│       ├── TileCheck.lua       # 瓦片交互检测
│       ├── Movement.lua        # 移动/攀爬/跳跃
│       ├── FragilePlatform.lua # 脆弱平台
│       ├── Particles.lua       # 粒子效果
│       ├── Camera.lua          # 相机跟随
│       ├── WorldPlay.lua       # 世界关卡切换
│       ├── DeathRespawn.lua    # 死亡/重生
│       ├── Lifecycle.lua       # 生命周期（进入/退出）
│       └── Renderer.lua        # 试玩模式渲染
│
├── gameplay/                   # 🎮 游戏运行时
│   ├── init.lua                # 游戏主循环（Start/Update/Render）
│   ├── Config.lua              # 游戏配置常量
│   ├── Physics.lua             # 物理/碰撞检测
│   ├── PlayerController.lua    # 玩家控制器
│   ├── LevelManager.lua        # 关卡加载/切换管理
│   ├── Animation.lua           # 动画系统（火焰/粒子/挤压）
│   ├── AudioManager.lua        # 音频管理
│   ├── Fireball.lua            # 火球投射物
│   ├── FlameDashChain.lua      # 火焰冲刺连锁
│   ├── PixelSystem.lua         # 像素状态系统
│   ├── Renderer.lua            # 渲染协调器
│   └── render/                 # 渲染子模块
│       ├── PixelFont.lua       # 像素字体数据
│       ├── Effects.lua         # 特效（篝火/粒子）
│       ├── Map.lua             # 地图绘制
│       ├── Tiles.lua           # 特殊瓦片绘制
│       ├── Player.lua          # 玩家/火球绘制
│       └── HUD.lua             # HUD/过渡动画
│
└── data/                       # 📦 关卡数据（JSON，不索引）
```

---

## 模块分类与职责

### 1. 入口层 (Entry)

| 文件 | 行数 | 职责 |
|------|------|------|
| `main.lua` | 108 | 应用入口，路由到 MainMenu → Editor/Game |
| `editor.lua` | 422 | 编辑器入口，事件订阅，NanoVG 渲染循环 |
| `game.lua` | 24 | 游戏入口（薄委托层） |
| `gameplay.lua` | 8 | gameplay 包入口（薄委托层） |
| `version.lua` | 4 | 版本号 |

### 2. 云存储系统 (cloud/)

| 文件 | 行数 | 核心 API |
|------|------|----------|
| `CloudStorage.lua` | 951 | `Init`, `Save`, `Load`, `Delete`, `ListLevels`, `ExportAll`, `ImportAll`, `InitPlayerParams`, `SaveWorldMap` |
| `cloud_recovery.lua` | 141 | `ScanCloud`, `RestoreFromResults`, `RestoreAll` |

### 3. 渲染系统 (rendering/)

| 文件 | 行数 | 核心 API |
|------|------|----------|
| `SolidRenderer.lua` | 2093 | `DrawBrick`, `DrawPillar`, `DrawSewer`, `DrawWater`, `DrawWaterSurface` |
| `FogOfWar.lua` | 1791 | `SetLightSources`, `Draw`, `AddLight`, `RemoveLight`, `IgniteLight`, `DrawLanterns`, `Serialize` |
| `CurtainRenderer.lua` | 402 | `DrawCurtain`, `TriggerSway`, `UpdateSway`, `IsCurtainAt` |

### 4. UI 系统 (ui/)

| 文件 | 行数 | 核心 API |
|------|------|----------|
| `MainMenu.lua` | 667 | 主菜单绘制、关卡选择、按钮交互 |
| `PauseMenu.lua` | 472 | 暂停菜单、设置面板 |

### 5. 关卡系统 (level/)

| 文件 | 行数 | 核心 API |
|------|------|----------|
| `LevelGenerator.lua` | 1138 | `Generate(difficulty, w, h)`, `GenerateValid(difficulty, retries, w, h)` |
| `WorldMapEditor.lua` | 774 | `Init`, `Draw`, `HandleMouseDown`, `AddNode`, `Save`, `Load` |

### 6. 编辑器系统 (editor/)

| 文件 | 行数 | 核心 API |
|------|------|----------|
| `Constants.lua` | 353 | 常量：`GRID`, `TILE`, `MODE`, `TOOLS` |
| `State.lua` | 472 | 编辑器运行时状态（当前工具、选区、缩放等） |
| `InputHandler.lua` | 2031 | `HandleUpdate`, `HandleKeyDown`, `HandleMouseDown` |
| `PlayMode.lua` | 552 | 试玩模式协调器，加载 10 个子模块 |
| `Toolbar.lua` | 1107 | `DrawTopBar`, `DrawToolbar`, `DrawBottomBar`, `HitTest*` |
| `Sidebar.lua` | 259 | `Draw`, `HitTest`, `Scroll` |
| `Dialogs.lua` | 1593 | `Open*Dialog`, `Draw`, `HandleKeyDown`, `HandleMouseDown` |
| `GridRenderer.lua` | 1253 | `Draw`（网格线、瓦片、选区、拖拽预览） |
| `FlameRenderer.lua` | 225 | `Draw`, `UpdateFlameAnim` |
| `PipeSystem.lua` | 707 | `Init`, `Update`, `CheckPlayerHit`, `DrawPipe` |
| `Placement.lua` | 273 | `PlaceTile`, `EraseTile`, `PlaceSpawn`, `PlacePipe` |
| `TileUtils.lua` | 146 | `GetTileType`, `MakeTileValue`, `ScreenToGrid`, `GridToScreen` |
| `MapData.lua` | 97 | `InitEmptyMap`, `ResizeCanvas` |
| `Persistence.lua` | 442 | `SaveLevel`, `LoadLevel`, `SerializeLevel`, `ApplyLevelData` |
| `LevelFileIO.lua` | 414 | `ExportLevel`, `ImportLevel`, `ExportAll`, `ListImportable` |
| `UndoSystem.lua` | 165 | `RecordTileChange`, `RecordBatch`, `Undo` |
| `CrossLevel.lua` | 404 | `LaunchProjectile`, `Update`, `CheckBoundaryCross` |
| `CloudPanel.lua` | 502 | `DrawPanel`, `OpenExportDialog`, `OpenImportDialog` |
| `GMTool.lua` | 362 | GM 面板（无限能量/生命、跳跃增强） |

### 7. 试玩模式子模块 (editor/play/)

采用 **Attach(M)** 模式，所有子模块挂载到 PlayMode 的 M 表上。

| 文件 | 行数 | 挂载方法 |
|------|------|----------|
| `Physics.lua` | 167 | `M.IsSolid`, `M.OnGround`, `M.Collides` |
| `TileCheck.lua` | 211 | `M.CheckTiles` (物品/陷阱检测) |
| `Movement.lua` | 438 | `M.HandleMovementInput`, `M.HandleClimbInput`, `M.HandleJumpInput`, `M.UpdateVerticalPhysics` |
| `FragilePlatform.lua` | 168 | `M.TriggerFragilePlatform`, `M.UpdateFragilePlatforms` |
| `Particles.lua` | 517 | `M.SpawnFlameTip`, `M.SpawnDashStreak`, `M.UpdateParticles` |
| `Camera.lua` | 37 | `M.UpdateCamera` |
| `WorldPlay.lua` | 355 | `M.UpdateWorldPlay`, `M.CheckWorldBoundary` |
| `DeathRespawn.lua` | 134 | `M.StartDeath`, `M.UpdateDeath`, `M.Respawn` |
| `Lifecycle.lua` | 170 | `M.StartPlayMode`, `M.ExitPlayMode` |
| `Renderer.lua` | 1439 | `M.DrawPlayMode` (所有 Draw* 函数) |

### 8. 游戏运行时 (gameplay/)

| 文件 | 行数 | 核心 API |
|------|------|----------|
| `init.lua` | 713 | `Start`, `HandleUpdate`, `HandleNanoVGRender`, 游戏主循环 |
| `Config.lua` | 128 | 游戏常量：`GRID`, `PLAYER_CONFIG`, `FLAME_COLORS` |
| `Physics.lua` | 239 | `IsSolid`, `PlayerCollidesAt`, `PlayerOnGround`, `GetSlopeAt` |
| `PlayerController.lua` | 534 | `ResetPlayer`, `PlayerJump`, `PlayerMoveOneGrid`, `UpdateVertical` |
| `LevelManager.lua` | 532 | `LoadLevelFromFile`, `TransitionToLevel`, `CheckBoundaryTransition` |
| `Animation.lua` | 351 | `UpdateFlameAnimFrame`, `UpdateFallParticles`, `TriggerJumpSquash` |
| `AudioManager.lua` | 178 | `Init`, `PlaySFX`, `PauseMusic`, `ResumeMusic` |
| `Fireball.lua` | 230 | `Shoot`, `Update`, `StartAbsorbAnim` |
| `FlameDashChain.lua` | 867 | `TryTrigger`, `Update`, 跨关卡冲刺逻辑 |
| `PixelSystem.lua` | 87 | `Init`, `StripPixels`, `RecoverPixels` |
| `Renderer.lua` | 169 | 渲染协调器，加载 6 个子模块 |

### 9. 游戏渲染子模块 (gameplay/render/)

采用 **Attach(M)** 模式，挂载到 gameplay/Renderer 的 M 表。

| 文件 | 行数 | 挂载方法 |
|------|------|----------|
| `PixelFont.lua` | 180 | `M.DrawPixelText` |
| `Effects.lua` | 266 | `M.DrawBonfire`, `M.DrawCampfire`, `M.DrawFuelBurst` |
| `Map.lua` | 384 | `M.DrawMap`, `M.CalcTileLighting` |
| `Tiles.lua` | 448 | `M.DrawCheckpointTile`, `M.DrawFuelPixelFlame`, `M.DrawAbilityPointTile` |
| `Player.lua` | 306 | `M.DrawFireball`, `M.DrawPlayer`, `M.DrawFallParticles` |
| `HUD.lua` | 255 | `M.DrawHUD`, `M.DrawLevelTransition`, `M.DrawDecorations` |

---

## 依赖关系图

```
main.lua
├── ui/MainMenu.lua
├── ui/PauseMenu.lua
├── cloud/cloud_recovery.lua
├── editor.lua
│   ├── editor/Constants.lua
│   ├── editor/State.lua
│   ├── editor/InputHandler.lua
│   ├── editor/PlayMode.lua ──→ editor/play/* (10 子模块)
│   ├── editor/Toolbar.lua
│   ├── editor/Sidebar.lua
│   ├── editor/Dialogs.lua
│   ├── editor/GridRenderer.lua
│   ├── editor/FlameRenderer.lua
│   ├── editor/PipeSystem.lua
│   ├── editor/Placement.lua
│   ├── editor/TileUtils.lua
│   ├── editor/MapData.lua
│   ├── editor/Persistence.lua
│   ├── editor/LevelFileIO.lua
│   ├── editor/UndoSystem.lua
│   ├── editor/CrossLevel.lua
│   ├── editor/CloudPanel.lua
│   ├── editor/GMTool.lua
│   ├── rendering/SolidRenderer.lua
│   ├── rendering/FogOfWar.lua
│   ├── rendering/CurtainRenderer.lua
│   ├── cloud/CloudStorage.lua
│   └── level/WorldMapEditor.lua
│
└── gameplay/init.lua
    ├── gameplay/Config.lua
    ├── gameplay/Physics.lua
    ├── gameplay/PlayerController.lua
    ├── gameplay/LevelManager.lua
    ├── gameplay/Animation.lua
    ├── gameplay/AudioManager.lua
    ├── gameplay/Fireball.lua
    ├── gameplay/FlameDashChain.lua
    ├── gameplay/PixelSystem.lua
    ├── gameplay/Renderer.lua ──→ gameplay/render/* (6 子模块)
    ├── rendering/SolidRenderer.lua
    ├── rendering/FogOfWar.lua
    ├── rendering/CurtainRenderer.lua
    ├── cloud/CloudStorage.lua
    └── level/LevelGenerator.lua
```

---

## 模块通信模式

### Inject 依赖注入

编辑器和游戏运行时模块使用 `M.Inject(deps)` 接收依赖：

```lua
-- 典型模式
function M.Inject(deps)
    M._Physics = deps.Physics
    M._FogOfWar = deps.FogOfWar
    M._State = deps.State
end
```

依赖在入口文件（`editor.lua` / `gameplay/init.lua`）的 `Start()` 中统一注入。

### Attach 子模块挂载

大模块拆分后使用 `Attach(M)` 模式：

```lua
-- 子模块文件
local Sub = {}
function Sub.Attach(M)
    function M.SomeMethod() ... end
end
return Sub
```

```lua
-- 父模块加载
require("editor.play.Physics").Attach(M)
require("editor.play.Movement").Attach(M)
```

### 共享状态约定

- `M._fieldName`：下划线前缀 = 模块内部共享（跨子模块可访问）
- `M.publicMethod`：无前缀 = 公开 API
- 闭包内 `local` 变量：子模块私有状态

---

## 关键入口点

| 场景 | 入口函数 | 位置 |
|------|---------|------|
| 应用启动 | `Start()` | `main.lua:89` |
| 进入编辑器 | `Start()` | `editor.lua:155` |
| 进入游戏 | `Start()` | `gameplay/init.lua:277` |
| 每帧更新 | `HandleUpdate()` | `editor.lua:335` / `gameplay/init.lua:493` |
| NanoVG 渲染 | `HandleNanoVGRender()` | `editor.lua:278` / `gameplay/init.lua:447` |
| 按键事件 | `HandleKeyDown()` | `editor.lua:373` / `gameplay/init.lua:679` |

---

## 文件大小分布

| 范围 | 文件数 | 占比 |
|------|--------|------|
| < 200 行 | 19 | 32% |
| 200-500 行 | 20 | 34% |
| 500-1000 行 | 10 | 17% |
| 1000-1500 行 | 5 | 8% |
| > 1500 行 | 5 | 8% |

仍超 1500 行的文件（待后续拆分）：
- `rendering/SolidRenderer.lua` (2093) - 砖/柱/下水道渲染（内聚性高）
- `editor/InputHandler.lua` (2031) - 输入分发（强耦合编辑器状态）
- `rendering/FogOfWar.lua` (1791) - 光照系统（算法内聚）
- `editor/Dialogs.lua` (1593) - 7 种对话框（可按类型拆分）
- `editor/play/Renderer.lua` (1439) - 试玩渲染（已从 4334 拆出）

---

*生成时间: 2026-06-04*
*适用版本: 重构后 V1.5.1+*
