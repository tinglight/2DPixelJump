------------------------------------------------------------
-- gameplay/render/PixelFont.lua — 像素字体渲染（委托到共享模块）
------------------------------------------------------------
local SharedPixelFont = require("rendering.PixelFont")

local PixelFont = {}

function PixelFont.Attach(M)
    --- 绘制像素风格文字（居中）
    ---@param text string 要绘制的文本（大写）
    ---@param centerX number 中心X
    ---@param centerY number 中心Y
    ---@param pixelSize number 每个像素块尺寸
    ---@param r number 红色 0-255
    ---@param g number 绿色 0-255
    ---@param b number 蓝色 0-255
    ---@param alpha number 透明度 0-255
    function M.DrawPixelText(text, centerX, centerY, pixelSize, r, g, b, alpha)
        SharedPixelFont.Draw(M.vg, text, centerX, centerY, pixelSize, r, g, b, alpha)
    end
end

return PixelFont
