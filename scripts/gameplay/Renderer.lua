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

function M.DrawBackground()
    local vg = M.vg

    -- 默认渐变背景
    local bg = nvgLinearGradient(vg, 0, 0, 0, M.screenDesignH,
        nvgRGBA(10, 5, 20, 255), nvgRGBA(30, 15, 40, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, M.screenDesignW, M.screenDesignH)
    nvgFillPaint(vg, bg)
    nvgFill(vg)

    -- 背景图铺满整个地图区域
    if Config.backgroundImage ~= "" then
        -- 路径变化时重新加载
        if bgImagePath_ ~= Config.backgroundImage then
            bgImageHandle_ = nvgCreateImage(vg, Config.backgroundImage, 0)
            bgImagePath_ = Config.backgroundImage
        end
        if bgImageHandle_ and bgImageHandle_ > 0 then
            local GRID = Config.GRID
            local mapW = Config.MAP_COLS * GRID
            local mapH = Config.MAP_ROWS * GRID
            local drawX = -M.cameraX
            local drawY = 0
            local imgPaint = nvgImagePattern(vg, drawX, drawY, mapW, mapH, 0, bgImageHandle_, Config.bgImageAlpha or 0.5)
            nvgBeginPath(vg)
            nvgRect(vg, drawX, drawY, mapW, mapH)
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
