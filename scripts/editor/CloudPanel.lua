-- ====================================================================
-- editor/CloudPanel.lua - 云端同步面板（导入/导出 .lua 关卡文件）
-- ====================================================================
--
-- 右下角按钮 → 展开面板（导出/导入选项）
-- 导出：弹出 UI.Modal 输入自定义名称 → 写入 data/levels/xxx.lua
-- 导入：弹出 UI.Modal 列出可导入文件 → 点击导入到云端
-- ====================================================================

local C = require "editor.Constants"
local S = require "editor.State"
local UI = require("urhox-libs/UI")
local LevelFileIO = require "editor.LevelFileIO"

local M = {}

-- ====================================================================
-- 外部依赖（通过 Inject 注入）
-- ====================================================================
local Persistence = nil
local CloudStorage = nil

function M.Inject(deps)
    Persistence = deps.Persistence
    CloudStorage = deps.CloudStorage
end

-- ====================================================================
-- 布局常量
-- ====================================================================
local BTN_W = 38
local BTN_H = 14
local BTN_MARGIN = 6

-- 面板按钮（展开后显示的导出/导入选项）
local PANEL_BTN_W = 36
local PANEL_BTN_H = 14
local PANEL_GAP = 4
local PANEL_PAD = 4

-- ====================================================================
-- 绘制：右下角"同步"按钮
-- ====================================================================
function M.DrawButton(vg)
    local statusH = 16
    -- 回收站按钮宽38，放在最右侧。同步按钮放在回收站左侧
    local trashBtnW = 38
    local btnX = S.screenDesignW - trashBtnW - BTN_MARGIN - BTN_W - BTN_MARGIN
    local btnY = S.screenDesignH - statusH - BTN_H - 4

    S.cloudBtnRect = { x = btnX, y = btnY, w = BTN_W, h = BTN_H }

    -- 鼠标悬停检测
    local mx = input:GetMousePosition().x / S.dpr / S.scaleF
    local my = input:GetMousePosition().y / S.dpr / S.scaleF
    local isHover = mx >= btnX and mx < btnX + BTN_W and my >= btnY and my < btnY + BTN_H

    -- 按钮背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, BTN_W, BTN_H, 3)
    if S.cloudPanelOpen then
        nvgFillColor(vg, nvgRGBA(50, 90, 140, 240))
    elseif isHover then
        nvgFillColor(vg, nvgRGBA(55, 75, 110, 240))
    else
        nvgFillColor(vg, nvgRGBA(35, 50, 75, 220))
    end
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, BTN_W, BTN_H, 3)
    nvgStrokeColor(vg, S.cloudPanelOpen and nvgRGBA(100, 160, 220, 220) or nvgRGBA(70, 100, 150, 180))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    -- 文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, S.cloudPanelOpen and nvgRGBA(180, 220, 255, 255) or nvgRGBA(150, 180, 210, 230))
    nvgText(vg, btnX + BTN_W * 0.5, btnY + BTN_H * 0.5, "同步")
end

-- ====================================================================
-- 绘制：展开面板（导出 / 导入两个按钮）
-- ====================================================================
function M.DrawPanel(vg)
    if not S.cloudPanelOpen then return end

    local statusH = 16
    local trashBtnW = 38
    local baseBtnX = S.screenDesignW - trashBtnW - BTN_MARGIN - BTN_W - BTN_MARGIN
    local baseBtnY = S.screenDesignH - statusH - BTN_H - 4

    -- 面板在按钮上方展开
    local panelW = PANEL_BTN_W * 2 + PANEL_GAP + PANEL_PAD * 2
    local panelH = PANEL_BTN_H + PANEL_PAD * 2
    local panelX = baseBtnX + BTN_W - panelW  -- 右对齐于主按钮
    local panelY = baseBtnY - panelH - 3

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 4)
    nvgFillColor(vg, nvgRGBA(25, 30, 45, 245))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 4)
    nvgStrokeColor(vg, nvgRGBA(70, 100, 150, 200))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    -- 导出按钮
    local exportX = panelX + PANEL_PAD
    local exportY = panelY + PANEL_PAD
    nvgBeginPath(vg)
    nvgRoundedRect(vg, exportX, exportY, PANEL_BTN_W, PANEL_BTN_H, 3)
    nvgFillColor(vg, nvgRGBA(40, 100, 70, 255))
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 8)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 255, 210, 255))
    nvgText(vg, exportX + PANEL_BTN_W * 0.5, exportY + PANEL_BTN_H * 0.5, "导出")

    -- 导入按钮
    local importX = exportX + PANEL_BTN_W + PANEL_GAP
    local importY = exportY
    nvgBeginPath(vg)
    nvgRoundedRect(vg, importX, importY, PANEL_BTN_W, PANEL_BTN_H, 3)
    nvgFillColor(vg, nvgRGBA(50, 80, 130, 255))
    nvgFill(vg)
    nvgFillColor(vg, nvgRGBA(180, 210, 255, 255))
    nvgText(vg, importX + PANEL_BTN_W * 0.5, importY + PANEL_BTN_H * 0.5, "导入")

    -- 存储面板按钮位置供命中检测
    S._cloudPanelExportRect = { x = exportX, y = exportY, w = PANEL_BTN_W, h = PANEL_BTN_H }
    S._cloudPanelImportRect = { x = importX, y = importY, w = PANEL_BTN_W, h = PANEL_BTN_H }
    S._cloudPanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }
end

-- ====================================================================
-- 命中检测
-- ====================================================================

--- 检测同步按钮点击
---@param mx number
---@param my number
---@return boolean
function M.HitTestButton(mx, my)
    if not S.cloudBtnRect then return false end
    local r = S.cloudBtnRect
    return mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
end

--- 检测面板内按钮点击
---@param mx number
---@param my number
---@return string|nil "export" | "import" | nil
function M.HitTestPanel(mx, my)
    if not S.cloudPanelOpen then return nil end

    local er = S._cloudPanelExportRect
    if er and mx >= er.x and mx < er.x + er.w and my >= er.y and my < er.y + er.h then
        return "export"
    end

    local ir = S._cloudPanelImportRect
    if ir and mx >= ir.x and mx < ir.x + ir.w and my >= ir.y and my < ir.y + ir.h then
        return "import"
    end

    return nil
end

--- 检测点击是否在面板区域内（包含主按钮）
---@param mx number
---@param my number
---@return boolean
function M.IsInsidePanel(mx, my)
    -- 主按钮区域
    if M.HitTestButton(mx, my) then return true end

    -- 展开面板区域
    if S.cloudPanelOpen and S._cloudPanelRect then
        local r = S._cloudPanelRect
        if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
            return true
        end
    end

    return false
end

-- ====================================================================
-- UI Modal 对话框
-- ====================================================================
local exportModal_ = nil
local exportTextField_ = nil
local importModal_ = nil

--- 关闭导出对话框
local function DestroyExportUI()
    if exportModal_ then
        exportModal_:Close()
        exportModal_ = nil
        exportTextField_ = nil
        UI.DisableAutoEventsInput()
    end
    S.cloudDialogMode = nil
end

--- 关闭导入对话框
local function DestroyImportUI()
    if importModal_ then
        importModal_:Close()
        importModal_ = nil
        UI.DisableAutoEventsInput()
    end
    S.cloudDialogMode = nil
end

--- 执行导出逻辑
local function DoExport(exportName)
    if not exportName or exportName == "" then
        S.SetMessage("导出名称不能为空", 2.0)
        return
    end

    -- 确保目录存在
    fileSystem:CreateDir("data")
    fileSystem:CreateDir("data/levels")

    -- 获取当前关卡文件名
    local currentFile = S.currentLevelFile
    if not currentFile or currentFile == "" then
        -- 如果没有在编辑某个已保存关卡，先保存
        S.SetMessage("请先保存当前关卡", 2.0)
        return
    end

    local ok, err = LevelFileIO.ExportLevel(currentFile, exportName)
    if ok then
        S.SetMessage("导出成功: " .. exportName .. ".lua", 2.5)
    else
        S.SetMessage("导出失败: " .. tostring(err), 3.0)
    end
end

--- 打开导出对话框
function M.OpenExportDialog()
    S.cloudPanelOpen = false
    S.cloudDialogMode = "export"

    UI.EnableAutoEventsInput()

    -- 默认名称：当前关卡的显示名称
    local defaultName = S.currentLevelDisplayName or ""
    if defaultName == "" then
        defaultName = "my_level"
    end

    exportTextField_ = UI.TextField {
        value = defaultName,
        placeholder = "输入导出文件名...",
        width = "100%",
        onSubmit = function(self, value)
            DoExport(value)
            DestroyExportUI()
        end,
    }

    exportModal_ = UI.Modal {
        title = "导出关卡为 .lua 文件",
        size = "sm",
        closeOnEscape = true,
        closeOnOverlay = true,
        onClose = function()
            exportModal_ = nil
            exportTextField_ = nil
            S.cloudDialogMode = nil
            UI.DisableAutoEventsInput()
        end,
    }

    exportModal_:AddContent(UI.Label {
        text = "文件将保存到 data/levels/ 目录，可随 git 提交",
        fontSize = 10,
        color = { 160, 160, 180, 255 },
    })
    exportModal_:AddContent(exportTextField_)

    -- Footer
    local footer = UI.Panel {
        flexDirection = "row",
        justifyContent = "flex-end",
        gap = 10,
        width = "100%",
    }
    footer:AddChild(UI.Button {
        text = "取消",
        variant = "secondary",
        onClick = function()
            DestroyExportUI()
        end,
    })
    footer:AddChild(UI.Button {
        text = "导出",
        variant = "primary",
        onClick = function()
            if exportTextField_ then
                local name = exportTextField_:GetValue() or ""
                DoExport(name)
                DestroyExportUI()
            end
        end,
    })
    exportModal_:SetFooter(footer)
    exportModal_:Open()
end

--- 打开导入对话框
function M.OpenImportDialog()
    S.cloudPanelOpen = false
    S.cloudDialogMode = "import"

    -- 确保目录存在
    fileSystem:CreateDir("data")
    fileSystem:CreateDir("data/levels")

    -- 读取可导入列表
    local importList = LevelFileIO.ListImportable()
    S.cloudImportList = importList

    UI.EnableAutoEventsInput()

    importModal_ = UI.Modal {
        title = "导入关卡文件",
        size = "md",
        closeOnEscape = true,
        closeOnOverlay = true,
        onClose = function()
            importModal_ = nil
            S.cloudDialogMode = nil
            S.cloudImportList = {}
            UI.DisableAutoEventsInput()
        end,
    }

    if #importList == 0 then
        importModal_:AddContent(UI.Label {
            text = "暂无可导入的关卡文件",
            fontSize = 12,
            color = { 160, 160, 180, 255 },
        })
        importModal_:AddContent(UI.Label {
            text = "请先将 .lua 关卡文件放入 scripts/data/levels/ 目录",
            fontSize = 10,
            color = { 120, 120, 140, 255 },
        })
    else
        importModal_:AddContent(UI.Label {
            text = "共 " .. #importList .. " 个文件，点击导入按钮添加为新关卡",
            fontSize = 10,
            color = { 160, 160, 180, 255 },
        })

        -- 文件列表
        local listPanel = UI.Panel {
            width = "100%",
            maxHeight = 150,
            overflow = "scroll",
            gap = 4,
        }

        for i, item in ipairs(importList) do
            local row = UI.Panel {
                flexDirection = "row",
                width = "100%",
                justifyContent = "space-between",
                alignItems = "center",
                paddingVertical = 2,
                paddingHorizontal = 6,
                backgroundColor = (i % 2 == 0) and { 40, 42, 55, 255 } or { 35, 37, 48, 255 },
                borderRadius = 3,
            }

            row:AddChild(UI.Panel {
                flexDirection = "column",
                flexShrink = 1,
                children = {
                    UI.Label {
                        text = item.displayName,
                        fontSize = 11,
                        color = { 220, 220, 240, 255 },
                    },
                    UI.Label {
                        text = item.name .. ".lua",
                        fontSize = 9,
                        color = { 120, 130, 150, 255 },
                    },
                },
            })

            row:AddChild(UI.Button {
                text = "导入",
                variant = "primary",
                size = "sm",
                onClick = function()
                    LevelFileIO.ImportLevel(item.name, function(ok, err)
                        if ok then
                            -- 刷新侧边栏
                            if Persistence and Persistence.RefreshSavedLevels then
                                Persistence.RefreshSavedLevels()
                            end
                        else
                            S.SetMessage("导入失败: " .. tostring(err), 3.0)
                        end
                    end)
                end,
            })

            listPanel:AddChild(row)
        end

        importModal_:AddContent(listPanel)
    end

    -- Footer: 关闭按钮
    local footer = UI.Panel {
        flexDirection = "row",
        justifyContent = "flex-end",
        width = "100%",
    }
    footer:AddChild(UI.Button {
        text = "关闭",
        variant = "secondary",
        onClick = function()
            DestroyImportUI()
        end,
    })
    importModal_:SetFooter(footer)
    importModal_:Open()
end

-- ====================================================================
-- 输入处理
-- ====================================================================

--- 处理鼠标点击（在 InputHandler 中调用）
---@param mx number 设计坐标
---@param my number 设计坐标
---@return boolean 是否消费了该事件
function M.HandleMouseDown(mx, my)
    -- 如果对话框打开中，阻止穿透
    if S.cloudDialogMode then
        return true
    end

    -- 检测面板内按钮
    if S.cloudPanelOpen then
        local action = M.HitTestPanel(mx, my)
        if action == "export" then
            M.OpenExportDialog()
            return true
        elseif action == "import" then
            M.OpenImportDialog()
            return true
        end

        -- 点击面板外部则关闭面板
        if not M.IsInsidePanel(mx, my) then
            S.cloudPanelOpen = false
            return true
        end
        return true
    end

    -- 检测主按钮点击
    if M.HitTestButton(mx, my) then
        S.cloudPanelOpen = not S.cloudPanelOpen
        return true
    end

    return false
end

return M
