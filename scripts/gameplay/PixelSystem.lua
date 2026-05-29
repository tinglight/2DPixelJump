------------------------------------------------------------
-- gameplay/PixelSystem.lua — 火焰像素状态管理
------------------------------------------------------------
local Config = require("gameplay.Config")

local M = {}

-- 运行时像素状态
M.pixelState = {}
M.totalPixels = 0
M.alivePixels = 0
M.stripOrder = {}   -- 从左右两侧向内的剥离顺序

--- 初始化像素状态
function M.Init()
    M.pixelState = {}
    M.totalPixels = 0
    local N = Config.PLAYER_CONFIG.pixelGridSize
    for row = 1, N do
        M.pixelState[row] = {}
        for col = 1, N do
            if Config.CHAR_SHAPE[row][col] == 1 then
                M.pixelState[row][col] = true
                M.totalPixels = M.totalPixels + 1
            else
                M.pixelState[row][col] = false
            end
        end
    end
    M.alivePixels = M.totalPixels

    -- 构建剥离顺序：从左右两侧向内剥离
    M.stripOrder = {}
    local cx = (N + 1) / 2

    for row = 1, N do
        for col = 1, N do
            if Config.CHAR_SHAPE[row][col] == 1 then
                local hDist = math.abs(col - cx)
                local vWeight = (N - row) * 0.1
                local priority = hDist + vWeight
                table.insert(M.stripOrder, { row = row, col = col, priority = priority })
            end
        end
    end
    table.sort(M.stripOrder, function(a, b) return a.priority > b.priority end)
end

--- 剥离 n 个像素点（从左右两侧）
function M.StripPixels(n)
    local stripped = 0
    for _, p in ipairs(M.stripOrder) do
        if stripped >= n then break end
        if M.pixelState[p.row][p.col] then
            M.pixelState[p.row][p.col] = false
            M.alivePixels = M.alivePixels - 1
            stripped = stripped + 1
        end
    end
end

--- 恢复 n 个像素点（从内层开始）
function M.RecoverPixels(n)
    local recovered = 0
    for i = #M.stripOrder, 1, -1 do
        if recovered >= n then break end
        local p = M.stripOrder[i]
        if not M.pixelState[p.row][p.col] then
            M.pixelState[p.row][p.col] = true
            M.alivePixels = M.alivePixels + 1
            recovered = recovered + 1
        end
    end
end

return M
