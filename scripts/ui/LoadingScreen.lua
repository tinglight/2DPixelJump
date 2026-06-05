-- ====================================================================
-- ui/LoadingScreen.lua - 像素风格加载界面
-- ====================================================================
-- 在编辑器世界试玩模式初始化期间显示 loading 画面，
-- 遮盖编辑器闪烁和背景加载延迟。
-- ====================================================================

local M = {}

-- ====================================================================
-- 状态
-- ====================================================================
M.active = false      -- loading 界面是否激活
M.ready = false       -- 关卡是否已加载完成（显示"按任意键继续"）
M.dismissed = false   -- 用户是否已按键关闭

-- 动画状态
M._clock = 0
M._dotCount = 0
M._barProgress = 0       -- 假进度条（0~1）
M._flickerTimer = 0
M._flickerOn = true
M._readyDelay = 0        -- ready 后延迟几帧才允许按键（等纹理上传 GPU）
M._READY_DELAY_TIME = 0.3  -- 等待 0.3 秒确保纹理就绪

-- 像素火焰动画帧
M._flameFrame = 1
M._flameTimer = 0

-- ====================================================================
-- 公开 API
-- ====================================================================

function M.Show()
    M.active = true
    M.ready = false
    M._levelReady = false  -- 关卡数据已加载（内部标记）
    M.dismissed = false
    M._clock = 0
    M._dotCount = 0
    M._barProgress = 0
    M._flickerTimer = 0
    M._flickerOn = true
    M._readyDelay = 0
    M._flameFrame = 1
    M._flameTimer = 0
end

function M.SetReady()
    -- 关卡已加载完毕，开始延迟计时（等纹理上传 GPU）
    -- 幂等：已调用过则不再重置计时器，避免每帧调用导致 delay 永远为 0
    if M._levelReady then return end
    M._levelReady = true
    M._readyDelay = 0
end

function M.Dismiss()
    M.dismissed = true
    M.active = false
end

function M.IsBlocking()
    return M.active and not M.dismissed
end

-- ====================================================================
-- 更新（每帧调用）
-- ====================================================================
function M.Update(dt)
    if not M.active then return end
    M._clock = M._clock + dt

    -- 加载中动画：点号循环
    M._dotCount = math.floor(M._clock * 3) % 4

    -- 关卡数据加载完成后，延迟一小段时间等纹理上传 GPU
    if M._levelReady and not M.ready then
        M._readyDelay = M._readyDelay + dt
        if M._readyDelay >= M._READY_DELAY_TIME then
            M.ready = true
        end
    end

    -- 假进度条：平滑增长到 0.85，ready 后快速到 1.0
    if M._levelReady then
        M._barProgress = math.min(1.0, M._barProgress + dt * 2.0)
    else
        M._barProgress = math.min(0.85, M._barProgress + dt * 0.3)
    end

    -- "按任意键" 闪烁
    M._flickerTimer = M._flickerTimer + dt
    if M._flickerTimer >= 0.5 then
        M._flickerTimer = M._flickerTimer - 0.5
        M._flickerOn = not M._flickerOn
    end

    -- 像素火焰帧动画
    M._flameTimer = M._flameTimer + dt
    if M._flameTimer >= 0.15 then
        M._flameTimer = M._flameTimer - 0.15
        M._flameFrame = (M._flameFrame % 4) + 1
    end
end

-- ====================================================================
-- 渲染（在 NanoVGRender 中调用）
-- ====================================================================
function M.Draw(vg, screenW, screenH)
    if not M.active then return end

    -- 全屏黑色背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(10, 8, 16, 255))
    nvgFill(vg)

    local cx = screenW * 0.5
    local cy = screenH * 0.5

    -- 绘制像素火焰图案（居中）
    M._DrawPixelFlame(vg, cx, cy - 40)

    -- 绘制进度条
    M._DrawProgressBar(vg, cx, cy + 20, screenW * 0.5)

    -- 绘制文字
    if M.ready then
        -- "按任意键继续" 闪烁显示
        if M._flickerOn then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 200, 80, 255))
            nvgText(vg, cx, cy + 50, "— 按任意键继续 —")
        end
    else
        -- "加载中..." 显示
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
        local dots = string.rep(".", M._dotCount)
        nvgText(vg, cx, cy + 50, "传火中" .. dots)
    end

    -- 底部装饰文字
    nvgFontSize(vg, 9)
    nvgFillColor(vg, nvgRGBA(80, 80, 100, 180))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgText(vg, cx, screenH - 8, "传火祭祀场")
end

-- ====================================================================
-- 内部：像素火焰绘制
-- ====================================================================
-- 用小方块模拟像素风格的火焰
local PIXEL = 4  -- 每个"像素"的实际大小

-- 火焰帧数据（简化的5x7像素图案，1=火焰核心,2=外焰,0=空）
local FLAME_FRAMES = {
    { -- frame 1
        {0,0,1,0,0},
        {0,1,1,1,0},
        {0,1,1,1,0},
        {1,1,2,1,1},
        {1,2,2,2,1},
        {0,2,2,2,0},
        {0,0,2,0,0},
    },
    { -- frame 2
        {0,0,0,1,0},
        {0,1,1,1,0},
        {0,1,1,0,0},
        {1,1,2,1,0},
        {1,2,2,2,1},
        {0,2,2,2,0},
        {0,0,2,0,0},
    },
    { -- frame 3
        {0,1,0,0,0},
        {0,1,1,1,0},
        {0,0,1,1,0},
        {0,1,2,1,1},
        {1,2,2,2,1},
        {0,2,2,2,0},
        {0,0,2,0,0},
    },
    { -- frame 4
        {0,0,1,0,0},
        {0,1,1,0,0},
        {0,1,1,1,0},
        {1,1,2,1,1},
        {0,2,2,2,1},
        {0,2,2,2,0},
        {0,0,2,0,0},
    },
}

function M._DrawPixelFlame(vg, cx, cy)
    local frame = FLAME_FRAMES[M._flameFrame]
    local rows = #frame
    local cols = #frame[1]
    local startX = cx - (cols * PIXEL) * 0.5
    local startY = cy - (rows * PIXEL) * 0.5

    for r = 1, rows do
        for c = 1, cols do
            local v = frame[r][c]
            if v > 0 then
                local x = startX + (c - 1) * PIXEL
                local y = startY + (r - 1) * PIXEL
                nvgBeginPath(vg)
                nvgRect(vg, x, y, PIXEL, PIXEL)
                if v == 1 then
                    -- 核心：亮黄/白
                    nvgFillColor(vg, nvgRGBA(255, 240, 120, 255))
                else
                    -- 外焰：橙红
                    nvgFillColor(vg, nvgRGBA(255, 100, 30, 255))
                end
                nvgFill(vg)
            end
        end
    end

    -- 火焰底座（小方块）
    local baseY = startY + rows * PIXEL
    nvgBeginPath(vg)
    nvgRect(vg, cx - PIXEL * 1.5, baseY, PIXEL * 3, PIXEL)
    nvgFillColor(vg, nvgRGBA(100, 60, 30, 255))
    nvgFill(vg)
end

-- ====================================================================
-- 内部：进度条绘制（像素风格）
-- ====================================================================
function M._DrawProgressBar(vg, cx, cy, totalWidth)
    local barW = totalWidth
    local barH = 8
    local x = cx - barW * 0.5
    local y = cy - barH * 0.5

    -- 外框（深灰像素边框）
    nvgBeginPath(vg)
    nvgRect(vg, x - 2, y - 2, barW + 4, barH + 4)
    nvgFillColor(vg, nvgRGBA(60, 60, 80, 255))
    nvgFill(vg)

    -- 内部背景
    nvgBeginPath(vg)
    nvgRect(vg, x, y, barW, barH)
    nvgFillColor(vg, nvgRGBA(20, 18, 30, 255))
    nvgFill(vg)

    -- 进度填充（像素块风格 - 分段）
    local fillW = barW * M._barProgress
    local segW = 6  -- 每段宽度
    local segGap = 2  -- 段间隔
    local segCount = math.floor(fillW / (segW + segGap))

    for i = 0, segCount - 1 do
        local sx = x + i * (segW + segGap)
        nvgBeginPath(vg)
        nvgRect(vg, sx, y + 1, segW, barH - 2)
        -- 颜色渐变：从橙到黄
        local t = i / math.max(1, math.floor(barW / (segW + segGap)) - 1)
        local r = math.floor(255 * (1 - t * 0.3))
        local g = math.floor(120 + 120 * t)
        nvgFillColor(vg, nvgRGBA(r, g, 20, 255))
        nvgFill(vg)
    end
end

return M
