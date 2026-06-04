------------------------------------------------------------
-- gameplay/render/HUD.lua — HUD、关卡过渡、装饰物、迷雾渲染
------------------------------------------------------------
local Config = require("gameplay.Config")
local EditorConstants = require("editor.Constants")
local FogOfWar = require("rendering.FogOfWar")
local GAME_VERSION = require("version")

local HUD = {}

function HUD.Attach(M)
    -- ====================================================================
    -- HUD
    -- ====================================================================
    function M.DrawHUD()
        local vg = M.vg
        local LevelManager = M._LevelManager
        local PixelSystem = M._PixelSystem
        local PlayerController = M._PlayerController

        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, M.screenDesignW, 22)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
        nvgFill(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        nvgFillColor(vg, nvgRGBA(200, 220, 255, 255))
        local levelLabel = LevelManager.currentTemplateName or LevelManager.currentLevelFile or ""
        nvgText(vg, 6, 11, levelLabel)

        local flamePercent = math.floor(PixelSystem.alivePixels / math.max(1, PixelSystem.totalPixels) * 100)
        local flameR = 255
        local flameG = math.floor(200 * (flamePercent / 100))
        nvgFillColor(vg, nvgRGBA(flameR, flameG, 30, 255))
        nvgText(vg, 90, 11, "FLAME:" .. flamePercent .. "%")

        nvgFillColor(vg, nvgRGBA(150, 255, 150, 255))
        nvgText(vg, 175, 11, "JUMP:" .. PlayerController.CalcJumpHeight() .. "G")

        nvgFillColor(vg, nvgRGBA(255, 140, 40, 255))
        nvgText(vg, 235, 11, "FUEL:" .. LevelManager.fuelCount)

        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 8)
        nvgFillColor(vg, nvgRGBA(100, 105, 120, 150))
        nvgText(vg, M.screenDesignW - 6, 11, "v" .. GAME_VERSION)

        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 150))
        local versionW = nvgTextBounds(vg, 0, 0, "v" .. GAME_VERSION) + 8
        nvgText(vg, M.screenDesignW - 6 - versionW, 11, "R:Retry N:Next 1/2/3:Diff")

        if M.gameState == Config.STATE_GAMEOVER then
            -- 半透明黑色遮罩
            nvgBeginPath(vg)
            nvgRect(vg, 0, 22, M.screenDesignW, M.screenDesignH - 22)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
            nvgFill(vg)
            -- 像素风格 "YOU DIE"
            M.DrawPixelText("YOU DIE", M.screenDesignW * 0.5, M.screenDesignH * 0.4, 4, 255, 60, 60, 255)
            -- 提示文字
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgText(vg, M.screenDesignW * 0.5, M.screenDesignH * 0.58, "R:Retry  N:New Level")
        elseif M.gameState == Config.STATE_WIN then
            -- 半透明黑色遮罩
            nvgBeginPath(vg)
            nvgRect(vg, 0, 22, M.screenDesignW, M.screenDesignH - 22)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
            nvgFill(vg)
            -- 像素风格 "YOU WIN"（需要添加 W 字符）
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 22)
            nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
            nvgText(vg, M.screenDesignW * 0.5, M.screenDesignH * 0.4, "FLAME ETERNAL!")
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgText(vg, M.screenDesignW * 0.5, M.screenDesignH * 0.55, "N:Next Level  R:Replay")
        end

        -- BONFIRE LIT 消息
        if M.bonfireMessage.active then
            local t = M.bonfireMessage.timer
            local dur = M.bonfireMessage.duration
            -- 淡入淡出
            local alpha = 255
            if t < 0.4 then
                alpha = math.floor(t / 0.4 * 255)
            elseif t > dur - 0.6 then
                alpha = math.floor((dur - t) / 0.6 * 255)
            end
            alpha = math.max(0, math.min(255, alpha))
            -- 像素风格 "BONFIRE LIT" 居中偏上
            M.DrawPixelText("BONFIRE LIT", M.screenDesignW * 0.5, M.screenDesignH * 0.35, 3, 255, 180, 40, alpha)
        end
    end

    -- ====================================================================
    -- 过渡遮罩
    -- ====================================================================
    function M.DrawLevelTransition()
        local LevelManager = M._LevelManager
        if not LevelManager.transition.active then return end
        if LevelManager.transition.alpha <= 0 then return end
        local vg = M.vg
        local a = math.floor(LevelManager.transition.alpha * 255)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, M.screenDesignW, M.screenDesignH)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, a))
        nvgFill(vg)
    end

    -- ====================================================================
    -- 装饰物渲染
    -- ====================================================================
    local gameDecoImageCache = {}  -- { [spritePath] = nvgImageHandle }

    function M.DrawDecorations()
        local LevelManager = M._LevelManager
        if not LevelManager.decorations or #LevelManager.decorations == 0 then return end

        local vg = M.vg
        local GRID = Config.GRID
        local DECO_TYPES = EditorConstants.DECORATION_TYPES
        local startCol = math.max(1, math.floor(M.cameraX / GRID) + 1)
        local visW = Config.DESIGN_W * (Config.PLAYER_CONFIG.cameraZoom or 1.0)
        local endCol = math.min(Config.MAP_COLS, startCol + math.ceil(visW / GRID) + 2)

        for _, deco in ipairs(LevelManager.decorations) do
            if deco.col >= startCol and deco.col <= endCol then
                local decoType = DECO_TYPES[deco.typeId]
                if not decoType then goto continueDeco end

                local px = (deco.col - 1) * GRID - M.cameraX
                local py = (deco.row - 1) * GRID

                if decoType.sprite and decoType.size then
                    local sizeW = decoType.size.w or 1
                    local sizeH = decoType.size.h or 1
                    -- 应用装饰物缩放（scale 存储为百分比，100=原始大小）
                    local scaleFactor = (deco.scale or 100) / 100
                    local drawW = sizeW * GRID * scaleFactor
                    local drawH = sizeH * GRID * scaleFactor
                    -- 锚点在中心：放置格的中心 = 装饰物图片的中心
                    local imgX = px + GRID * 0.5 - drawW * 0.5
                    local imgY = py + GRID * 0.5 - drawH * 0.5

                    -- 加载/缓存贴图
                    if not gameDecoImageCache[decoType.sprite] then
                        local handle = nvgCreateImage(vg, decoType.sprite, 0)
                        gameDecoImageCache[decoType.sprite] = handle or -1
                    end

                    local imgHandle = gameDecoImageCache[decoType.sprite]
                    if imgHandle and imgHandle > 0 then
                        local paint = nvgImagePattern(vg, imgX, imgY, drawW, drawH, 0, imgHandle, 1.0)
                        nvgBeginPath(vg)
                        nvgRect(vg, imgX, imgY, drawW, drawH)
                        nvgFillPaint(vg, paint)
                        nvgFill(vg)
                    end
                else
                    -- 无贴图 fallback
                    local color = decoType.color or {180, 140, 220}
                    nvgBeginPath(vg)
                    nvgRect(vg, px, py, GRID, GRID)
                    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 150))
                    nvgFill(vg)
                end

                ::continueDeco::
            end
        end
    end

    -- ====================================================================
    -- 迷雾与灯笼渲染
    -- ====================================================================
    function M.DrawFogOfWar()
        local vg = M.vg
        local GRID = Config.GRID
        local LevelManager = M._LevelManager
        local PixelSystem = M._PixelSystem
        local PlayerController = M._PlayerController
        local Physics = M._Physics

        local startCol = math.max(1, math.floor(M.cameraX / GRID) + 1)
        local visW = Config.DESIGN_W * (Config.PLAYER_CONFIG.cameraZoom or 1.0)
        local endCol = math.min(Config.MAP_COLS, startCol + math.ceil(visW / GRID) + 2)

        -- 将玩家动态光源临时加入光源列表
        local sources = FogOfWar.GetLightSources()
        local playerLightIdx = nil
        local flameRatio = PixelSystem.alivePixels / math.max(1, PixelSystem.totalPixels)
        local playerDiameter = Config.PLAYER_CONFIG.defaultLightDiameter * flameRatio
        if playerDiameter >= 1 then
            local player = PlayerController.player
            local playerS = Physics.PlayerGridSize()
            local lightCol = player.gridX + math.floor(playerS * 0.5)
            local lightRow = player.gridY + math.floor(playerS * 0.5)
            table.insert(sources, {
                col = lightCol,
                row = lightRow,
                diameter = playerDiameter,
                feather = 0.5,
            })
            playerLightIdx = #sources
        end

        FogOfWar.SetLightSources(sources)
        FogOfWar.Draw(vg, {
            gridSize = GRID,
            startCol = startCol,
            endCol = endCol,
            startRow = 1,
            endRow = Config.MAP_ROWS,
            offsetX = M.cameraX,
            offsetY = 0,
            zoomLevel = 1.0,
            mapX = 0,
            mapY = 0,
        })

        -- 移除临时的玩家动态光源，恢复原始列表
        if playerLightIdx then
            table.remove(sources, playerLightIdx)
        end

        -- 在迷雾上方绘制像素提灯（仅地图光源，不含玩家）
        FogOfWar.DrawLanterns(vg, {
            gridSize = GRID,
            offsetX = M.cameraX,
            offsetY = 0,
            zoomLevel = 1.0,
            mapX = 0,
            mapY = 0,
        })

        -- 绘制熄灭的提灯（暗色调，等待被火球点亮）
        FogOfWar.DrawUnlitLanterns(vg, {
            gridSize = GRID,
            offsetX = M.cameraX,
            offsetY = 0,
            zoomLevel = 1.0,
            mapX = 0,
            mapY = 0,
        })
    end
end

return HUD
