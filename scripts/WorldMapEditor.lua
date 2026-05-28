-- ====================================================================
-- WorldMapEditor.lua - 世界地图编辑器（关卡连通关系可视化）
-- ====================================================================
--
-- 功能：
-- 1. 将已保存关卡拖入画布作为蓝图节点
-- 2. 左键拖拽蓝图自由放置位置
-- 3. 右键蓝图进入连接模式，鼠标带线跟随
-- 4. 连接模式中左键点击另一蓝图 → 建立连通关系
-- 5. 连通方向由相对位置自动计算
--
-- ====================================================================

local CloudStorage = require "CloudStorage"

local WorldMapEditor = {}

-- ====================================================================
-- 常量
-- ====================================================================
local NODE_W = 100       -- 蓝图节点宽度
local NODE_H = 60        -- 蓝图节点高度
local NODE_RADIUS = 6    -- 圆角半径
local GRID_SIZE = 40     -- 背景网格大小

-- 方向常量
local DIR_RIGHT = "right"
local DIR_LEFT  = "left"
local DIR_UP    = "up"
local DIR_DOWN  = "down"

-- 方向翻转表
local DIR_REVERSE = {
    [DIR_RIGHT] = DIR_LEFT,
    [DIR_LEFT]  = DIR_RIGHT,
    [DIR_UP]    = DIR_DOWN,
    [DIR_DOWN]  = DIR_UP,
}

-- 方向中文名
local DIR_NAMES = {
    [DIR_RIGHT] = "右",
    [DIR_LEFT]  = "左",
    [DIR_UP]    = "上",
    [DIR_DOWN]  = "下",
}

-- ====================================================================
-- 状态
-- ====================================================================
local vg = nil

-- 世界地图数据
local mapData = {
    nodes = {},          -- { id, file, name, x, y }
    connections = {},    -- { fromId, toId, direction }
    nextId = 1,
}

-- 相机
local camX = 0
local camY = 0
local zoom = 1.0
local ZOOM_MIN = 0.3
local ZOOM_MAX = 3.0

-- 交互状态
local dragState = nil       -- nil or { nodeId, offsetX, offsetY }
local connectMode = nil     -- nil or { fromId }
local selectedNode = nil    -- 当前选中的节点 id
local mouseX, mouseY = 0, 0  -- 当前鼠标世界坐标

-- 中键拖拽视窗
local midDragging = false
local midDragLastX = 0
local midDragLastY = 0

-- 双击检测
local lastClickTime = 0         -- 上次左键点击时间
local lastClickNodeId = nil     -- 上次点击的节点 id
local DOUBLE_CLICK_TIME = 0.4   -- 双击判定时间窗口（秒）

-- 外部回调
local msgCallback = nil     -- function(text, duration)
local doubleClickCallback = nil  -- function(nodeFile, nodeName) 双击节点回调

-- 屏幕尺寸（由外部传入）
local screenW, screenH = 480, 272
local topBarH = 22
local bottomBarH = 56
local sidebarW = 100

-- ====================================================================
-- 辅助函数
-- ====================================================================

--- 屏幕坐标转世界坐标
local function ScreenToWorld(sx, sy)
    local wx = (sx + camX) / zoom
    local wy = (sy - topBarH + camY) / zoom
    return wx, wy
end

--- 世界坐标转屏幕坐标
local function WorldToScreen(wx, wy)
    local sx = wx * zoom - camX
    local sy = wy * zoom - camY + topBarH
    return sx, sy
end

--- 检测点是否在节点矩形内
local function PointInNode(wx, wy, node)
    return wx >= node.x and wx <= node.x + NODE_W
       and wy >= node.y and wy <= node.y + NODE_H
end

--- 根据两个节点的相对位置计算连通方向
local function CalcDirection(fromNode, toNode)
    local fromCX = fromNode.x + NODE_W * 0.5
    local fromCY = fromNode.y + NODE_H * 0.5
    local toCX = toNode.x + NODE_W * 0.5
    local toCY = toNode.y + NODE_H * 0.5

    local dx = toCX - fromCX
    local dy = toCY - fromCY

    if math.abs(dx) >= math.abs(dy) then
        return dx >= 0 and DIR_RIGHT or DIR_LEFT
    else
        return dy >= 0 and DIR_DOWN or DIR_UP
    end
end

--- 获取节点边缘的连接锚点（根据方向）
local function GetEdgePoint(node, dir)
    local cx = node.x + NODE_W * 0.5
    local cy = node.y + NODE_H * 0.5
    if dir == DIR_RIGHT then
        return node.x + NODE_W, cy
    elseif dir == DIR_LEFT then
        return node.x, cy
    elseif dir == DIR_DOWN then
        return cx, node.y + NODE_H
    elseif dir == DIR_UP then
        return cx, node.y
    end
    return cx, cy
end

--- 根据 id 查找节点
local function FindNodeById(id)
    for _, node in ipairs(mapData.nodes) do
        if node.id == id then return node end
    end
    return nil
end

--- 检查两个节点间是否已有连接
local function ConnectionExists(fromId, toId)
    for _, conn in ipairs(mapData.connections) do
        if (conn.fromId == fromId and conn.toId == toId) or
           (conn.fromId == toId and conn.toId == fromId) then
            return true
        end
    end
    return false
end

--- 显示消息
local function ShowMsg(text, duration)
    if msgCallback then msgCallback(text, duration or 2.0) end
end

-- ====================================================================
-- 公共接口
-- ====================================================================

--- 初始化
function WorldMapEditor.Init(vgCtx, msgCb, dblClickCb)
    vg = vgCtx
    msgCallback = msgCb
    doubleClickCallback = dblClickCb
    -- 加载世界地图
    WorldMapEditor.Load()
end

--- 设置布局参数
function WorldMapEditor.SetLayout(sw, sh, tbH, bbH, sbW)
    screenW = sw
    screenH = sh
    topBarH = tbH
    bottomBarH = bbH
    sidebarW = sbW
end

--- 加载世界地图数据
function WorldMapEditor.Load()
    local data = CloudStorage.LoadWorldMap()
    if data and data.nodes then
        mapData.nodes = data.nodes or {}
        mapData.connections = data.connections or {}
        mapData.nextId = data.nextId or 1
    else
        mapData = { nodes = {}, connections = {}, nextId = 1 }
    end
end

--- 保存世界地图数据
function WorldMapEditor.Save()
    CloudStorage.SaveWorldMap(mapData, function(ok, err)
        if ok then
            ShowMsg("世界地图已保存", 1.5)
        else
            ShowMsg("世界地图保存失败: " .. (err or "未知错误"), 3.0)
        end
    end)
end

--- 添加蓝图节点
function WorldMapEditor.AddNode(file, name)
    -- 检查是否已经添加过
    for _, node in ipairs(mapData.nodes) do
        if node.file == file then
            ShowMsg("该关卡已在地图中", 2.0)
            return
        end
    end

    -- 在画布中心附近放置
    local wx = camX / zoom + (screenW - sidebarW) * 0.5 / zoom - NODE_W * 0.5
    local wy = camY / zoom + (screenH - topBarH - bottomBarH) * 0.5 / zoom - NODE_H * 0.5

    local node = {
        id = mapData.nextId,
        file = file,
        name = name,
        x = wx,
        y = wy,
    }
    mapData.nextId = mapData.nextId + 1
    table.insert(mapData.nodes, node)
    selectedNode = node.id
    ShowMsg("已添加: " .. name, 1.5)
end

--- 获取所有连通数据（供 main.lua 使用）
function WorldMapEditor.GetConnections()
    return mapData.connections, mapData.nodes
end

--- 更新节点显示名称（关卡重命名后同步）
---@param file string 关卡文件名
---@param newName string 新显示名称
function WorldMapEditor.UpdateNodeName(file, newName)
    for _, node in ipairs(mapData.nodes) do
        if node.file == file then
            node.name = newName
            return true
        end
    end
    return false
end

--- 获取当前是否处于连接模式
function WorldMapEditor.IsConnecting()
    return connectMode ~= nil
end

-- ====================================================================
-- 渲染
-- ====================================================================

--- 绘制背景网格
local function DrawGrid()
    local mapW = screenW - sidebarW
    local mapH = screenH - topBarH - bottomBarH

    -- 暗色背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, topBarH, mapW, mapH)
    nvgFillColor(vg, nvgRGBA(18, 16, 28, 255))
    nvgFill(vg)

    -- 点阵网格
    local gridZ = GRID_SIZE * zoom
    local startCol = math.floor(camX / gridZ)
    local startRow = math.floor(camY / gridZ)
    local endCol = startCol + math.ceil(mapW / gridZ) + 1
    local endRow = startRow + math.ceil(mapH / gridZ) + 1

    for row = startRow, endRow do
        for col = startCol, endCol do
            local sx = col * gridZ - camX
            local sy = row * gridZ - camY + topBarH
            if sx >= 0 and sx <= mapW and sy >= topBarH and sy <= topBarH + mapH then
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, 1.5)
                nvgFillColor(vg, nvgRGBA(50, 50, 70, 120))
                nvgFill(vg)
            end
        end
    end
end

--- 绘制连接线
local function DrawConnections()
    for _, conn in ipairs(mapData.connections) do
        local fromNode = FindNodeById(conn.fromId)
        local toNode = FindNodeById(conn.toId)
        if not fromNode or not toNode then goto continueConn end

        local dir = conn.direction
        local fx, fy = GetEdgePoint(fromNode, dir)
        local tx, ty = GetEdgePoint(toNode, DIR_REVERSE[dir])

        -- 转屏幕坐标
        local sfx, sfy = WorldToScreen(fx, fy)
        local stx, sty = WorldToScreen(tx, ty)

        -- 连接线
        nvgBeginPath(vg)
        nvgMoveTo(vg, sfx, sfy)
        nvgLineTo(vg, stx, sty)
        nvgStrokeColor(vg, nvgRGBA(100, 200, 255, 200))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)

        -- 箭头（指向 to）
        local angle = math.atan(sty - sfy, stx - sfx)
        local arrLen = 10
        local arrAngle = 0.45
        nvgBeginPath(vg)
        nvgMoveTo(vg, stx, sty)
        nvgLineTo(vg, stx - arrLen * math.cos(angle - arrAngle), sty - arrLen * math.sin(angle - arrAngle))
        nvgMoveTo(vg, stx, sty)
        nvgLineTo(vg, stx - arrLen * math.cos(angle + arrAngle), sty - arrLen * math.sin(angle + arrAngle))
        nvgStrokeColor(vg, nvgRGBA(100, 200, 255, 200))
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)

        -- 方向标注（线段中点）
        local midX = (sfx + stx) * 0.5
        local midY = (sfy + sty) * 0.5
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 标注背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, midX - 10, midY - 7, 20, 14, 3)
        nvgFillColor(vg, nvgRGBA(20, 20, 40, 220))
        nvgFill(vg)
        nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
        nvgText(vg, midX, midY, DIR_NAMES[dir] or "?")

        ::continueConn::
    end
end

--- 绘制连接模式跟随线
local function DrawConnectingLine()
    if not connectMode then return end

    local fromNode = FindNodeById(connectMode.fromId)
    if not fromNode then return end

    local fcx = fromNode.x + NODE_W * 0.5
    local fcy = fromNode.y + NODE_H * 0.5
    local sfx, sfy = WorldToScreen(fcx, fcy)

    -- 虚线效果（用多段短线模拟）
    local dx = mouseX - sfx
    local dy = mouseY - sfy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then return end

    local dashLen = 8
    local gapLen = 5
    local totalStep = dashLen + gapLen
    local steps = math.floor(dist / totalStep)

    nvgBeginPath(vg)
    for i = 0, steps do
        local t0 = (i * totalStep) / dist
        local t1 = math.min(1, (i * totalStep + dashLen) / dist)
        local x0 = sfx + dx * t0
        local y0 = sfy + dy * t0
        local x1 = sfx + dx * t1
        local y1 = sfy + dy * t1
        nvgMoveTo(vg, x0, y0)
        nvgLineTo(vg, x1, y1)
    end
    nvgStrokeColor(vg, nvgRGBA(255, 200, 80, 200))
    nvgStrokeWidth(vg, 2.0)
    nvgStroke(vg)

    -- 鼠标位置小圆
    nvgBeginPath(vg)
    nvgCircle(vg, mouseX, mouseY, 5)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 80, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

--- 绘制蓝图节点
local function DrawNodes()
    for _, node in ipairs(mapData.nodes) do
        local sx, sy = WorldToScreen(node.x, node.y)
        local w = NODE_W * zoom
        local h = NODE_H * zoom

        -- 选中高亮
        local isSelected = (selectedNode == node.id)
        local isConnectFrom = connectMode and connectMode.fromId == node.id

        -- 卡片背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, w, h, NODE_RADIUS * zoom)
        if isConnectFrom then
            nvgFillColor(vg, nvgRGBA(60, 50, 20, 240))
        elseif isSelected then
            nvgFillColor(vg, nvgRGBA(35, 40, 60, 240))
        else
            nvgFillColor(vg, nvgRGBA(30, 32, 48, 240))
        end
        nvgFill(vg)

        -- 边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, w, h, NODE_RADIUS * zoom)
        if isConnectFrom then
            nvgStrokeColor(vg, nvgRGBA(255, 200, 80, 255))
            nvgStrokeWidth(vg, 2.5)
        elseif isSelected then
            nvgStrokeColor(vg, nvgRGBA(100, 180, 255, 255))
            nvgStrokeWidth(vg, 2.0)
        else
            nvgStrokeColor(vg, nvgRGBA(70, 80, 110, 200))
            nvgStrokeWidth(vg, 1.0)
        end
        nvgStroke(vg)

        -- 标题栏
        local titleH = 18 * zoom
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx + 1, sy + 1, w - 2, titleH, NODE_RADIUS * zoom)
        nvgFillColor(vg, nvgRGBA(50, 55, 80, 200))
        nvgFill(vg)

        -- 关卡名称
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.max(8, 11 * zoom))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 240, 255, 255))
        nvgText(vg, sx + w * 0.5, sy + titleH * 0.5, node.name)

        -- 文件名
        nvgFontSize(vg, math.max(6, 8 * zoom))
        nvgFillColor(vg, nvgRGBA(140, 140, 170, 200))
        nvgText(vg, sx + w * 0.5, sy + h * 0.65, node.file)

        -- 连接指示器（四个方向的小点）
        local dotR = 4 * zoom
        local dirs = { DIR_RIGHT, DIR_LEFT, DIR_UP, DIR_DOWN }
        for _, dir in ipairs(dirs) do
            local hasConn = false
            for _, conn in ipairs(mapData.connections) do
                if conn.fromId == node.id and conn.direction == dir then
                    hasConn = true
                    break
                end
            end
            if hasConn then
                local ex, ey = GetEdgePoint(node, dir)
                local esx, esy = WorldToScreen(ex, ey)
                nvgBeginPath(vg)
                nvgCircle(vg, esx, esy, dotR)
                nvgFillColor(vg, nvgRGBA(100, 200, 255, 255))
                nvgFill(vg)
            end
        end
    end
end

--- 绘制提示信息
local function DrawHints()
    local mapW = screenW - sidebarW
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(140, 140, 170, 180))

    local hintY = screenH - bottomBarH - 4
    if connectMode then
        nvgFillColor(vg, nvgRGBA(255, 200, 80, 220))
        nvgText(vg, 6, hintY, "连接模式: 左键点击目标关卡 | 右键/ESC取消")
    else
        nvgText(vg, 6, hintY, "左键:拖拽 | 双击:编辑关卡 | 右键:连接 | Del:删除 | WASD:平移 | 滚轮:缩放")
    end

    -- 缩放比例
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(140, 140, 170, 180))
    nvgText(vg, mapW - 4, hintY, math.floor(zoom * 100) .. "%")
end

--- 主渲染
function WorldMapEditor.Draw()
    local mapW = screenW - sidebarW
    local mapH = screenH - topBarH - bottomBarH

    nvgSave(vg)
    nvgScissor(vg, 0, topBarH, mapW, mapH)

    DrawGrid()
    DrawConnections()
    DrawNodes()
    DrawConnectingLine()

    nvgRestore(vg)

    DrawHints()
end

-- ====================================================================
-- 更新
-- ====================================================================

function WorldMapEditor.Update(dt)
    -- WASD 平移相机
    local scrollSpeed = 200
    if input:GetKeyDown(KEY_A) and not input:GetKeyDown(KEY_CTRL) then
        camX = camX - scrollSpeed * dt
    end
    if input:GetKeyDown(KEY_D) and not input:GetKeyDown(KEY_CTRL) then
        camX = camX + scrollSpeed * dt
    end
    if input:GetKeyDown(KEY_W) and not input:GetKeyDown(KEY_CTRL) then
        camY = camY - scrollSpeed * dt
    end
    if input:GetKeyDown(KEY_S) and not input:GetKeyDown(KEY_CTRL) then
        camY = camY + scrollSpeed * dt
    end

    -- 中键拖拽视窗
    if midDragging then
        local dx = mouseX - midDragLastX
        local dy = mouseY - midDragLastY
        camX = camX - dx
        camY = camY - dy
        midDragLastX = mouseX
        midDragLastY = mouseY
    end

    -- 拖拽更新
    if dragState then
        local mx = input:GetMousePosition().x
        local my = input:GetMousePosition().y
        -- 需要外部传入 dpr/scaleF，先用全局变量方式
        local node = FindNodeById(dragState.nodeId)
        if node then
            local wx, wy = ScreenToWorld(mouseX, mouseY - topBarH + topBarH)
            node.x = wx - dragState.offsetX
            node.y = wy - dragState.offsetY
        end
    end
end

-- ====================================================================
-- 输入处理
-- ====================================================================

--- 更新鼠标坐标（屏幕设计坐标）
function WorldMapEditor.UpdateMouse(mx, my)
    mouseX = mx
    mouseY = my
end

--- 鼠标按下
function WorldMapEditor.HandleMouseDown(button, mx, my)
    local mapW = screenW - sidebarW
    -- 只处理地图区域内的点击
    if mx < 0 or mx > mapW or my < topBarH or my > screenH - bottomBarH then
        return false
    end

    -- 中键拖拽视窗
    if button == MOUSEB_MIDDLE then
        midDragging = true
        midDragLastX = mx
        midDragLastY = my
        return true
    end

    local wx, wy = ScreenToWorld(mx, my)

    if button == MOUSEB_LEFT then
        -- 连接模式：左键点击目标节点
        if connectMode then
            for _, node in ipairs(mapData.nodes) do
                if PointInNode(wx, wy, node) and node.id ~= connectMode.fromId then
                    -- 检查是否已有连接
                    if ConnectionExists(connectMode.fromId, node.id) then
                        ShowMsg("连接已存在", 1.5)
                    else
                        -- 建立连接
                        local fromNode = FindNodeById(connectMode.fromId)
                        if fromNode then
                            local dir = CalcDirection(fromNode, node)
                            -- 正向连接
                            table.insert(mapData.connections, {
                                fromId = connectMode.fromId,
                                toId = node.id,
                                direction = dir,
                            })
                            -- 反向连接
                            table.insert(mapData.connections, {
                                fromId = node.id,
                                toId = connectMode.fromId,
                                direction = DIR_REVERSE[dir],
                            })
                            ShowMsg(fromNode.name .. " ←→ " .. node.name .. " (" .. DIR_NAMES[dir] .. ")", 2.0)
                        end
                    end
                    connectMode = nil
                    return true
                end
            end
            -- 点击空白取消连接模式
            connectMode = nil
            return true
        end

        -- 普通模式：左键点击/双击/拖拽节点
        local now = os.clock()
        for i = #mapData.nodes, 1, -1 do  -- 从顶层开始检测
            local node = mapData.nodes[i]
            if PointInNode(wx, wy, node) then
                -- 双击检测：同一节点在时间窗口内被点击两次
                if lastClickNodeId == node.id and (now - lastClickTime) < DOUBLE_CLICK_TIME then
                    -- 双击触发：进入该关卡编辑模式
                    lastClickNodeId = nil
                    lastClickTime = 0
                    if doubleClickCallback then
                        doubleClickCallback(node.file, node.name)
                    end
                    return true
                end
                -- 记录本次点击用于双击判定
                lastClickNodeId = node.id
                lastClickTime = now

                dragState = {
                    nodeId = node.id,
                    offsetX = wx - node.x,
                    offsetY = wy - node.y,
                }
                selectedNode = node.id
                return true
            end
        end

        -- 点击空白取消选择
        lastClickNodeId = nil
        lastClickTime = 0
        selectedNode = nil
        return true

    elseif button == MOUSEB_RIGHT then
        -- 连接模式中右键取消
        if connectMode then
            connectMode = nil
            ShowMsg("取消连接", 1.0)
            return true
        end

        -- 右键节点进入连接模式
        for i = #mapData.nodes, 1, -1 do
            local node = mapData.nodes[i]
            if PointInNode(wx, wy, node) then
                connectMode = { fromId = node.id }
                selectedNode = node.id
                ShowMsg("连接模式: 点击目标关卡", 2.0)
                return true
            end
        end
    end

    return false
end

--- 鼠标松开
function WorldMapEditor.HandleMouseUp(button, mx, my)
    if button == MOUSEB_MIDDLE then
        midDragging = false
        return
    end
    if button == MOUSEB_LEFT then
        dragState = nil
    end
end

--- 鼠标滚轮
function WorldMapEditor.HandleMouseWheel(wheel, mx, my)
    local mapW = screenW - sidebarW
    if mx < 0 or mx > mapW or my < topBarH or my > screenH - bottomBarH then
        return false
    end

    local oldZoom = zoom
    if wheel > 0 then
        zoom = zoom * 1.2
    elseif wheel < 0 then
        zoom = zoom / 1.2
    end
    zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, zoom))

    -- 以鼠标为中心缩放
    local mapRelX = mx
    local mapRelY = my - topBarH
    local worldX = (mapRelX + camX) / oldZoom
    local worldY = (mapRelY + camY) / oldZoom
    camX = worldX * zoom - mapRelX
    camY = worldY * zoom - mapRelY

    return true
end

--- 键盘按下
function WorldMapEditor.HandleKeyDown(key)
    if key == KEY_ESCAPE then
        if connectMode then
            connectMode = nil
            ShowMsg("取消连接", 1.0)
            return true
        end
    end

    if key == KEY_DELETE or key == KEY_BACKSPACE then
        if selectedNode then
            -- 删除选中节点及其所有连接
            for i = #mapData.nodes, 1, -1 do
                if mapData.nodes[i].id == selectedNode then
                    table.remove(mapData.nodes, i)
                    break
                end
            end
            -- 删除相关连接
            for i = #mapData.connections, 1, -1 do
                local conn = mapData.connections[i]
                if conn.fromId == selectedNode or conn.toId == selectedNode then
                    table.remove(mapData.connections, i)
                end
            end
            ShowMsg("已删除节点", 1.5)
            selectedNode = nil
            return true
        end
    end

    -- Ctrl+S 保存
    if key == KEY_S and input:GetKeyDown(KEY_CTRL) then
        WorldMapEditor.Save()
        return true
    end

    return false
end

--- 获取地图数据（供外部序列化或游戏加载）
function WorldMapEditor.GetMapData()
    return mapData
end

return WorldMapEditor
