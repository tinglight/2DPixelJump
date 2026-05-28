-- ====================================================================
-- editor/UndoSystem.lua - 撤销系统
-- ====================================================================

local C = require "editor.Constants"
local S = require "editor.State"

local M = {}

-- ====================================================================
-- 撤销状态
-- ====================================================================
M.stack = {}
M.maxHistory = 200
M.drawMergeTime = 3.0
M.currentAction = nil
M.lastTime = 0
M.dirty = false
M.saveTimer = 0
M.saveDelay = 1.0

-- ====================================================================
-- 核心操作
-- ====================================================================

--- 记录地块变更
---@param col number
---@param row number
---@param oldVal number
---@param newVal number
function M.RecordTileChange(col, row, oldVal, newVal)
    if oldVal == newVal then return end
    local now = os.clock()

    if M.currentAction and (S.isDrawing or S.isErasing) and (now - M.currentAction.timestamp) < M.drawMergeTime then
        table.insert(M.currentAction.deltas, {
            col = col, row = row,
            oldVal = oldVal, newVal = newVal,
        })
        M.currentAction.lastTime = now
    else
        local action = {
            deltas = {{ col = col, row = row, oldVal = oldVal, newVal = newVal }},
            timestamp = now,
            lastTime = now,
            actionType = (S.isDrawing or S.isErasing) and "draw" or "single",
        }
        table.insert(M.stack, action)
        if #M.stack > M.maxHistory then
            table.remove(M.stack, 1)
        end
        if S.isDrawing or S.isErasing then
            M.currentAction = action
        end
    end

    M.dirty = true
    M.saveTimer = M.saveDelay
    M.lastTime = now
end

--- 记录 spawn 变更
---@param oldCol number
---@param oldRow number
---@param newCol number
---@param newRow number
function M.RecordSpawnChange(oldCol, oldRow, newCol, newRow)
    if oldCol == newCol and oldRow == newRow then return end
    local now = os.clock()
    local action = {
        deltas = {},
        timestamp = now,
        lastTime = now,
        actionType = "spawn",
        spawnChange = {
            oldCol = oldCol, oldRow = oldRow,
            newCol = newCol, newRow = newRow,
        },
    }
    if oldCol >= 1 and oldCol <= S.MAP_COLS and oldRow >= 1 and oldRow <= S.MAP_ROWS then
        table.insert(action.deltas, {
            col = oldCol, row = oldRow,
            oldVal = C.TILE.SPAWN, newVal = C.TILE.EMPTY,
        })
    end
    table.insert(action.deltas, {
        col = newCol, row = newRow,
        oldVal = C.TILE.EMPTY, newVal = C.TILE.SPAWN,
    })
    table.insert(M.stack, action)
    if #M.stack > M.maxHistory then
        table.remove(M.stack, 1)
    end
    M.dirty = true
    M.saveTimer = M.saveDelay
end

--- 执行撤销
function M.Undo()
    if #M.stack == 0 then
        S.SetMessage("无可撤销操作", 1.5)
        return
    end
    local action = table.remove(M.stack)
    for i = #action.deltas, 1, -1 do
        local d = action.deltas[i]
        S.levelData[d.row][d.col] = d.oldVal
    end
    if action.spawnChange then
        S.spawnCol = action.spawnChange.oldCol
        S.spawnRow = action.spawnChange.oldRow
    else
        for i = #action.deltas, 1, -1 do
            local d = action.deltas[i]
            if d.oldVal == C.TILE.SPAWN then
                S.spawnCol = d.col
                S.spawnRow = d.row
            end
        end
    end
    S.SetMessage("撤销 (" .. #action.deltas .. " 格)", 1.5)
    M.dirty = true
    M.saveTimer = M.saveDelay
end

--- 结束当前绘制动作合并
function M.FinalizeDrawAction()
    M.currentAction = nil
end

--- 重置撤销历史
function M.Reset()
    M.stack = {}
    M.currentAction = nil
    M.dirty = false
    M.saveTimer = 0
end

--- 标记为脏
function M.MarkDirty()
    M.dirty = true
    M.saveTimer = M.saveDelay
end

return M
