------------------------------------------------------------
-- gameplay/Renderer.lua — 渲染系统协调器
-- 实际逻辑拆分到 gameplay/render/ 子模块中
------------------------------------------------------------
local Config = require("gameplay.Config")
local SolidRenderer = require("rendering.SolidRenderer")
local CurtainRenderer = require("rendering.CurtainRenderer")

-- 子模块
local PixelFont = require("gameplay.render.PixelFont")
local Effects   = require("gameplay.render.Effects")
local Map       = require("gameplay.render.Map")
local Tiles     = require("gameplay.render.Tiles")
local Player    = require("gameplay.render.Player")
local HUD       = require("gameplay.render.HUD")

local M = {}

-- ====================================================================
-- 子模块挂载
-- ====================================================================
PixelFont.Attach(M)
Effects.Attach(M)
Map.Attach(M)
Tiles.Attach(M)
Player.Attach(M)
HUD.Attach(M)

-- ====================================================================
-- 依赖注入
-- ====================================================================
-- 私有依赖字段（供子模块通过 M._XXX 访问）
M._Physics = nil
M._PixelSystem = nil
M._PlayerController = nil
M._LevelManager = nil
M._Animation = nil

function M.Inject(deps)
    M._Physics = deps.Physics
    M._PixelSystem = deps.PixelSystem
    M._PlayerController = deps.PlayerController
    M._LevelManager = deps.LevelManager
    M._Animation = deps.Animation

    -- 设置碰撞检测器用于光照阴影遮挡
    SolidRenderer.SetCollisionChecker(function(col, row)
        return deps.Physics.IsSolidForLight(col, row)
    end)

    -- 设置柳条检测器用于光照衰减
    SolidRenderer.SetCurtainChecker(function(col, row)
        return CurtainRenderer.IsCurtainAt(col, row, deps.LevelManager.levelData,
            require("level.LevelGenerator").TILE, deps.Physics.GetTileType)
    end)
end

-- ====================================================================
-- 渲染上下文
-- ====================================================================
M.vg = nil
M.screenDesignW = 0
M.screenDesignH = 0
M.cameraX = 0
M.gameTime = 0
M.gameState = Config.STATE_PLAYING

--- 设置渲染上下文（每帧调用一次，在任何 Draw* 之前）
function M.SetContext(ctx)
    M.vg = ctx.vg
    M.screenDesignW = ctx.screenDesignW
    M.screenDesignH = ctx.screenDesignH
    M.cameraX = ctx.cameraX
    M.gameTime = ctx.gameTime
    M.gameState = ctx.gameState
end

-- ====================================================================
-- 背景
-- ====================================================================
local bgImageHandle_ = nil
local bgImagePath_ = ""
local bgCache_ = {}  -- 相邻关卡背景图预加载缓存 { [path] = nvgHandle }

--- 预加载背景图片（在关卡加载完成后立即调用，避免 fadeIn 时黑屏）
---@param vgCtx userdata NanoVG 上下文
---@param path string 背景图路径（可为空字符串表示无背景）
function M.PreloadBackgroundImage(vgCtx, path)
    if not vgCtx then return end
    if not path or path == "" then
        bgImageHandle_ = nil
        bgImagePath_ = ""
        return
    end
    if bgImagePath_ == path then return end  -- 已加载，无需重复
    -- 优先从缓存获取
    if bgCache_[path] then
        bgImageHandle_ = bgCache_[path]
    else
        bgImageHandle_ = nvgCreateImage(vgCtx, path, 0)
        bgCache_[path] = bgImageHandle_
    end
    bgImagePath_ = path
end

--- 预加载所有相邻关卡的背景图到缓存（在当前关卡加载完成后调用）
--- 利用玩家游玩当前关卡的时间完成 GPU 纹理上传
---@param vgCtx userdata NanoVG 上下文
---@param worldMapData table 世界地图数据
---@param currentLevelFile string 当前关卡文件名
function M.PreloadConnectedBackgrounds(vgCtx, worldMapData, currentLevelFile)
    if not vgCtx or not worldMapData or not currentLevelFile then return end

    -- 找到当前节点 ID
    local currentNodeId = nil
    for _, node in ipairs(worldMapData.nodes or {}) do
        if node.file == currentLevelFile then
            currentNodeId = node.id
            break
        end
    end
    if not currentNodeId then return end

    -- 收集所有相邻关卡的背景图路径
    local neededPaths = {}
    -- 保留当前关卡自身的路径
    if Config.backgroundImage and Config.backgroundImage ~= "" then
        neededPaths[Config.backgroundImage] = true
    end

    for _, conn in ipairs(worldMapData.connections or {}) do
        if conn.fromId == currentNodeId then
            local targetFile = nil
            for _, node in ipairs(worldMapData.nodes) do
                if node.id == conn.toId then
                    targetFile = node.file
                    break
                end
            end
            if targetFile then
                -- 从本地 data/levels/ 或 CloudStorage 读取关卡 JSON
                local json = nil
                local localPath = "data/levels/" .. targetFile
                if fileSystem:FileExists(localPath) then
                    local file = File(localPath, FILE_READ)
                    if file and file:IsOpen() then
                        json = file:ReadString()
                        file:Close()
                    end
                end
                if not json or json == "" then
                    -- fallback CloudStorage（由 LevelManager 注入的依赖）
                    local CloudStorage = M._LevelManager and require("cloud.CloudStorage")
                    if CloudStorage then
                        json = CloudStorage.Load(targetFile)
                    end
                end
                if json then
                    local ok2, data = pcall(cjson.decode, json)
                    if ok2 and data and data.backgroundImage and data.backgroundImage ~= "" then
                        neededPaths[data.backgroundImage] = true
                    end
                end
            end
        end
    end

    -- 释放缓存中不再需要的句柄
    for path, handle in pairs(bgCache_) do
        if not neededPaths[path] then
            nvgDeleteImage(vgCtx, handle)
            bgCache_[path] = nil
        end
    end

    -- 预加载缺失的背景图
    for path, _ in pairs(neededPaths) do
        if not bgCache_[path] then
            bgCache_[path] = nvgCreateImage(vgCtx, path, 0)
        end
    end
end

function M.DrawBackground()
    local vg = M.vg

    -- 默认渐变背景
    local bg = nvgLinearGradient(vg, 0, 0, 0, M.screenDesignH,
        nvgRGBA(10, 5, 20, 255), nvgRGBA(30, 15, 40, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, M.screenDesignW, M.screenDesignH)
    nvgFillPaint(vg, bg)
    nvgFill(vg)

    -- 背景图
    if Config.backgroundImage ~= "" then
        -- 路径变化时重新加载（兜底，正常流程已通过 PreloadBackgroundImage 提前加载）
        if bgImagePath_ ~= Config.backgroundImage then
            -- 优先从缓存获取
            if bgCache_[Config.backgroundImage] then
                bgImageHandle_ = bgCache_[Config.backgroundImage]
            else
                bgImageHandle_ = nvgCreateImage(vg, Config.backgroundImage, 0)
                bgCache_[Config.backgroundImage] = bgImageHandle_
            end
            bgImagePath_ = Config.backgroundImage
        end
        if bgImageHandle_ and bgImageHandle_ > 0 then
            local GRID = Config.GRID
            local drawX, drawY, drawW, drawH
            if Config.bgStretchToCanvas then
                -- 拉伸为整个画布（地图）大小
                drawX = -M.cameraX
                drawY = 0
                drawW = Config.MAP_COLS * GRID
                drawH = Config.MAP_ROWS * GRID
            else
                -- 铺满可见相机区域
                drawX = 0
                drawY = 0
                drawW = M.screenDesignW
                drawH = M.screenDesignH
            end
            local imgPaint = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, bgImageHandle_, Config.bgImageAlpha or 0.5)
            nvgBeginPath(vg)
            nvgRect(vg, drawX, drawY, drawW, drawH)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        end
    else
        bgImageHandle_ = nil
        bgImagePath_ = ""
    end
end

-- ====================================================================
-- 网格
-- ====================================================================
function M.DrawGrid()
    local vg = M.vg
    local GRID = Config.GRID
    local startCol = math.max(1, math.floor(M.cameraX / GRID) + 1)
    local visW = Config.DESIGN_W * (Config.PLAYER_CONFIG.cameraZoom or 1.0)
    local endCol = math.min(Config.MAP_COLS, startCol + math.ceil(visW / GRID) + 2)

    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        local x = (col - 1) * GRID - M.cameraX
        nvgMoveTo(vg, x, 0)
        nvgLineTo(vg, x, Config.MAP_ROWS * GRID)
    end
    for row = 1, Config.MAP_ROWS + 1 do
        local y = (row - 1) * GRID
        local x0 = (startCol - 1) * GRID - M.cameraX
        local x1 = (endCol) * GRID - M.cameraX
        nvgMoveTo(vg, x0, y)
        nvgLineTo(vg, x1, y)
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 15))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)

    nvgBeginPath(vg)
    for col = startCol, endCol + 1 do
        if (col - 1) % 5 == 0 then
            local x = (col - 1) * GRID - M.cameraX
            nvgMoveTo(vg, x, 0)
            nvgLineTo(vg, x, Config.MAP_ROWS * GRID)
        end
    end
    for row = 1, Config.MAP_ROWS + 1 do
        if (row - 1) % 5 == 0 then
            local y = (row - 1) * GRID
            local x0 = (startCol - 1) * GRID - M.cameraX
            local x1 = (endCol) * GRID - M.cameraX
            nvgMoveTo(vg, x0, y)
            nvgLineTo(vg, x1, y)
        end
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 35))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

return M
