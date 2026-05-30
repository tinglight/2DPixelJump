------------------------------------------------------------
-- MainMenu.lua — 游戏主菜单界面
------------------------------------------------------------
-- 包含: 背景图、开始游戏、继续游戏、设置、退出按钮
-- 右上角编辑器入口（扳手图标）
-- 所有按钮有 Dark Souls 风格点击音效
------------------------------------------------------------

local UI = require("urhox-libs/UI")
local CloudStorage = require "CloudStorage"

local MainMenu = {}

-- ====================================================================
-- 状态
-- ====================================================================
local hasSaveData = false
local initialized = false

-- UI 引用
---@type Modal
local settingsModal = nil
---@type Modal
local exitModal = nil
---@type Modal
local newGameModal = nil
---@type any
local rootPanel = nil

-- 音效
---@type Sound
local clickSound = nil
---@type SoundSource
local clickSource = nil
---@type Node
local audioNode = nil
---@type Scene
local audioScene = nil

-- BGM
---@type Sound
local bgmSound = nil
---@type SoundSource
local bgmSource = nil

-- 音量设置
local musicVolume = 0.25
local sfxVolume = 1.0
local musicMuted = false
local sfxMuted = false

-- 回调
local onStartGame = nil   -- 开始新游戏
local onContinue = nil    -- 继续游戏
local onOpenEditor = nil  -- 打开编辑器

-- ====================================================================
-- 音效播放
-- ====================================================================

local function PlayClickSound()
    if clickSource and clickSound then
        clickSource.gain = sfxMuted and 0 or sfxVolume
        clickSource:Play(clickSound)
    end
end

-- ====================================================================
-- 存档检测
-- ====================================================================

local function CheckSaveData(callback)
    -- 使用 CloudStorage 检查是否有关卡进度
    clientCloud:Get("editor_index", {
        ok = function(values)
            local indexData = values.editor_index
            if indexData and indexData.nextIndex and indexData.nextIndex > 1 then
                hasSaveData = true
            else
                hasSaveData = false
            end
            if callback then callback() end
        end,
        err = function()
            hasSaveData = false
            if callback then callback() end
        end
    })
end

-- ====================================================================
-- 关卡检测：异步检测世界地图是否有节点
-- ====================================================================
---@type any
local noLevelModal = nil

local function CheckWorldMapAndStart(callback)
    local CS = require "CloudStorage"
    CS.InitWorldMap(function(ok)
        local worldMap = CS.LoadWorldMap()
        local hasNodes = worldMap and worldMap.nodes and #worldMap.nodes > 0
        if hasNodes then
            if callback then callback() end
        else
            -- 没有关卡，弹窗提示
            if noLevelModal then
                noLevelModal:Open()
            end
        end
    end)
end

-- ====================================================================
-- UI 构建
-- ====================================================================

local function BuildUI()
    -- 按钮通用样式（像素风格，纯文字无边框）
    local btnHeight = 48
    local btnFontSize = 22

    -- 纯文字颜色方案
    local btnTextNormal = { 180, 170, 150, 255 }        -- 默认：暗金灰
    local btnTextHover = { 255, 220, 100, 255 }          -- 悬停/选中：亮金色
    local btnTextPressed = { 255, 180, 50, 255 }         -- 按下：深金色

    -- 通用按钮配置（纯文字，无背景无边框，悬停变色）
    local function MenuButton(props)
        local btn = UI.Button {
            text = props.text,
            height = btnHeight,
            fontSize = btnFontSize,
            textColor = btnTextNormal,
            backgroundColor = { 0, 0, 0, 0 },
            hoverBackgroundColor = { 0, 0, 0, 0 },
            pressedBackgroundColor = { 0, 0, 0, 0 },
            borderWidth = 0,
            borderRadius = 0,
            paddingHorizontal = 8,
            onPointerEnter = function(event, self)
                self.props.textColor = btnTextHover
            end,
            onPointerLeave = function(event, self)
                self.props.textColor = btnTextNormal
            end,
            onClick = function(self)
                self.props.textColor = btnTextPressed
                PlayClickSound()
                if props.onClick then props.onClick(self) end
            end
        }
        return btn
    end

    -- ============================================================
    -- 设置弹窗
    -- ============================================================
    local musicSlider = UI.Slider {
        min = 0, max = 100, value = math.floor(musicVolume * 100),
        trackHeight = 4,
        thumbSize = 14,
        onChange = function(self, v)
            musicVolume = v / 100
            musicMuted = false
            audio:SetMasterGain("Music", musicVolume)
        end
    }

    local sfxSlider = UI.Slider {
        min = 0, max = 100, value = math.floor(sfxVolume * 100),
        trackHeight = 4,
        thumbSize = 14,
        onChange = function(self, v)
            sfxVolume = v / 100
            sfxMuted = false
            audio:SetMasterGain("Effect", sfxVolume)
        end
    }

    local musicMuteBtn = UI.Button {
        text = musicMuted and "🔇" or "🔊",
        width = 36, height = 36,
        fontSize = 18,
        backgroundColor = { 50, 50, 50, 200 },
        hoverBackgroundColor = { 70, 70, 70, 220 },
        pressedBackgroundColor = { 90, 90, 90, 240 },
        borderRadius = 18,
        onClick = function(self)
            PlayClickSound()
            musicMuted = not musicMuted
            audio:SetMasterGain("Music", musicMuted and 0 or musicVolume)
            self:SetText(musicMuted and "🔇" or "🔊")
        end
    }

    local sfxMuteBtn = UI.Button {
        text = sfxMuted and "🔇" or "🔊",
        width = 36, height = 36,
        fontSize = 18,
        backgroundColor = { 50, 50, 50, 200 },
        hoverBackgroundColor = { 70, 70, 70, 220 },
        pressedBackgroundColor = { 90, 90, 90, 240 },
        borderRadius = 18,
        onClick = function(self)
            PlayClickSound()
            sfxMuted = not sfxMuted
            audio:SetMasterGain("Effect", sfxMuted and 0 or sfxVolume)
            self:SetText(sfxMuted and "🔇" or "🔊")
        end
    }

    settingsModal = UI.Modal {
        title = "设置",
        isOpen = false,
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            self:Close()
        end,
        children = {
            -- 音效设置区域
            UI.Label { text = "音频设置", fontSize = 14, textColor = { 200, 180, 140, 255 }, marginBottom = 8 },

            -- 音乐音量
            UI.Panel {
                flexDirection = "row", alignItems = "center", width = "100%", marginBottom = 12,
                children = {
                    UI.Label { text = "音乐", fontSize = 13, textColor = { 180, 170, 150, 255 }, width = 40 },
                    UI.Panel { flexGrow = 1, marginHorizontal = 8, children = { musicSlider } },
                    musicMuteBtn,
                }
            },

            -- 音效音量
            UI.Panel {
                flexDirection = "row", alignItems = "center", width = "100%", marginBottom = 16,
                children = {
                    UI.Label { text = "音效", fontSize = 13, textColor = { 180, 170, 150, 255 }, width = 40 },
                    UI.Panel { flexGrow = 1, marginHorizontal = 8, children = { sfxSlider } },
                    sfxMuteBtn,
                }
            },
        }
    }

    -- ============================================================
    -- 退出确认弹窗
    -- ============================================================
    exitModal = UI.Modal {
        title = "退出游戏",
        isOpen = false,
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = false,
        children = {
            UI.Label {
                text = "确定要退出游戏吗？",
                fontSize = 14,
                textColor = { 200, 190, 170, 255 },
                textAlign = "center",
                width = "100%",
                marginBottom = 16,
            },
            UI.Panel {
                flexDirection = "row", justifyContent = "center", width = "100%", gap = 16,
                children = {
                    UI.Button {
                        text = "确定",
                        width = 80, height = 36, fontSize = 13,
                        backgroundColor = { 120, 50, 40, 220 },
                        hoverBackgroundColor = { 150, 60, 50, 240 },
                        pressedBackgroundColor = { 180, 70, 50, 255 },
                        textColor = { 255, 220, 200, 255 },
                        borderRadius = 4,
                        onClick = function(self)
                            PlayClickSound()
                            engine:Exit()
                        end
                    },
                    UI.Button {
                        text = "返回",
                        width = 80, height = 36, fontSize = 13,
                        backgroundColor = { 50, 50, 50, 200 },
                        hoverBackgroundColor = { 70, 70, 70, 220 },
                        pressedBackgroundColor = { 90, 90, 90, 240 },
                        textColor = btnTextNormal,
                        borderRadius = 4,
                        onClick = function(self)
                            PlayClickSound()
                            exitModal:Close()
                        end
                    },
                }
            }
        }
    }

    -- ============================================================
    -- 新游戏确认弹窗（有存档时弹出）
    -- ============================================================
    newGameModal = UI.Modal {
        title = "开始新游戏",
        isOpen = false,
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = false,
        children = {
            UI.Label {
                text = "开始新游戏将重置现有进度，确定继续吗？",
                fontSize = 14,
                textColor = { 200, 190, 170, 255 },
                textAlign = "center",
                width = "100%",
                marginBottom = 16,
            },
            UI.Panel {
                flexDirection = "row", justifyContent = "center", width = "100%", gap = 16,
                children = {
                    UI.Button {
                        text = "确定",
                        width = 80, height = 36, fontSize = 13,
                        backgroundColor = { 120, 50, 40, 220 },
                        hoverBackgroundColor = { 150, 60, 50, 240 },
                        pressedBackgroundColor = { 180, 70, 50, 255 },
                        textColor = { 255, 220, 200, 255 },
                        borderRadius = 4,
                        onClick = function(self)
                            PlayClickSound()
                            newGameModal:Close()
                            -- 重置存档后开始新游戏
                            MainMenu.ResetSaveAndStart()
                        end
                    },
                    UI.Button {
                        text = "返回",
                        width = 80, height = 36, fontSize = 13,
                        backgroundColor = { 50, 50, 50, 200 },
                        hoverBackgroundColor = { 70, 70, 70, 220 },
                        pressedBackgroundColor = { 90, 90, 90, 240 },
                        textColor = btnTextNormal,
                        borderRadius = 4,
                        onClick = function(self)
                            PlayClickSound()
                            newGameModal:Close()
                        end
                    },
                }
            }
        }
    }

    -- ============================================================
    -- 无关卡提示弹窗
    -- ============================================================
    noLevelModal = UI.Modal {
        title = "提示",
        isOpen = false,
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = false,
        children = {
            UI.Label {
                text = "没有关卡可运行，请先在编辑器中创建关卡。",
                fontSize = 14,
                textColor = { 200, 190, 170, 255 },
                textAlign = "center",
                width = "100%",
                marginBottom = 16,
            },
            UI.Panel {
                flexDirection = "row", justifyContent = "center", width = "100%",
                children = {
                    UI.Button {
                        text = "确定",
                        width = 80, height = 36, fontSize = 13,
                        backgroundColor = { 80, 60, 40, 220 },
                        hoverBackgroundColor = { 100, 80, 50, 240 },
                        pressedBackgroundColor = { 120, 90, 60, 255 },
                        textColor = { 255, 220, 180, 255 },
                        borderRadius = 4,
                        onClick = function(self)
                            PlayClickSound()
                            noLevelModal:Close()
                        end
                    },
                }
            }
        }
    }

    -- ============================================================
    -- 按钮列表
    -- ============================================================
    local buttonChildren = {}

    -- 继续游戏按钮（有存档时才显示，且在开始游戏上方）
    if hasSaveData then
        table.insert(buttonChildren, MenuButton {
            text = "继续游戏",
            onClick = function(self)
                CheckWorldMapAndStart(function()
                    if onContinue then onContinue() end
                end)
            end
        })
    end

    -- 开始游戏按钮
    table.insert(buttonChildren, MenuButton {
        text = "开始游戏",
        onClick = function(self)
            if hasSaveData then
                newGameModal:Open()
            else
                CheckWorldMapAndStart(function()
                    if onStartGame then onStartGame() end
                end)
            end
        end
    })

    -- 设置按钮
    table.insert(buttonChildren, MenuButton {
        text = "设置",
        onClick = function(self)
            settingsModal:Open()
        end
    })

    -- 退出按钮
    table.insert(buttonChildren, MenuButton {
        text = "退出游戏",
        onClick = function(self)
            exitModal:Open()
        end
    })

    -- ============================================================
    -- 编辑器按钮（右上角扳手图标）
    -- ============================================================
    local editorBtn = UI.Button {
        text = "🔧",
        width = 40, height = 40,
        fontSize = 18,
        backgroundColor = { 40, 40, 40, 180 },
        hoverBackgroundColor = { 60, 55, 45, 220 },
        pressedBackgroundColor = { 80, 70, 50, 240 },
        borderRadius = 20,
        borderWidth = 1,
        borderColor = { 100, 90, 70, 150 },
        position = "absolute",
        top = 16, right = 16,
        onClick = function(self)
            PlayClickSound()
            if onOpenEditor then onOpenEditor() end
        end
    }

    -- ============================================================
    -- 主界面根布局
    -- ============================================================
    rootPanel = UI.Panel {
        width = "100%", height = "100%",
        -- 背景图
        backgroundImage = "image/传火祭祀场背景_20260530100114.png",
        backgroundSize = "cover",
        children = {
            -- 遮罩层
            UI.Panel {
                width = "100%", height = "100%",
                backgroundColor = { 0, 0, 0, 60 },
                justifyContent = "flex-end",
                alignItems = "center",
                paddingBottom = "18%",
                children = {
                    -- 按钮容器（居中偏下，无背景）
                    UI.Panel {
                        alignItems = "center",
                        gap = 6,
                        children = buttonChildren,
                    }
                }
            },

            -- 编辑器按钮（绝对定位右上角）
            editorBtn,

            -- 弹窗（绝对定位层）
            settingsModal,
            exitModal,
            newGameModal,
            noLevelModal,
        }
    }

    UI.SetRoot(rootPanel)
end

-- ====================================================================
-- 公共接口
-- ====================================================================

--- 初始化主菜单
---@param callbacks table { onStartGame, onContinue, onOpenEditor }
function MainMenu.Init(callbacks)
    if initialized then return end

    onStartGame = callbacks.onStartGame
    onContinue = callbacks.onContinue
    onOpenEditor = callbacks.onOpenEditor

    -- 初始化 UI 系统（像素字体风格）
    UI.Init({
        theme = "dark",
        fonts = {
            { name = "sans", path = "Fonts/zpix.ttf" },
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 初始化音效
    audioScene = Scene()
    audioScene:CreateComponent("Octree")
    audioNode = audioScene:CreateChild("MenuAudio")
    clickSource = audioNode:CreateComponent("SoundSource")
    clickSource.soundType = "Effect"
    clickSource.gain = sfxVolume
    clickSound = cache:GetResource("Sound", "audio/sfx/ui_click.ogg")

    -- BGM 初始化
    bgmSource = audioNode:CreateComponent("SoundSource")
    bgmSource.soundType = "Music"
    bgmSource.gain = musicVolume
    bgmSound = cache:GetResource("Sound", "audio/menu_bgm.ogg")
    if bgmSound then
        bgmSound.looped = true
        bgmSource:Play(bgmSound)
    end

    -- 确保音频系统可用
    audio:SetMasterGain("Effect", sfxVolume)
    audio:SetMasterGain("Music", musicVolume)
    audio:SetMasterGain("Master", 1.0)

    -- 检查存档并构建 UI
    CheckSaveData(function()
        BuildUI()
        initialized = true
        print("[MainMenu] Init OK, hasSave=" .. tostring(hasSaveData))
    end)
end

--- 重置存档并开始新游戏
function MainMenu.ResetSaveAndStart()
    -- 重置云端存档索引
    clientCloud:Set("editor_index", { nextIndex = 1 }, {
        ok = function()
            print("[MainMenu] Save data reset")
            CheckWorldMapAndStart(function()
                if onStartGame then onStartGame() end
            end)
        end,
        err = function()
            print("[MainMenu] Failed to reset save, starting anyway")
            CheckWorldMapAndStart(function()
                if onStartGame then onStartGame() end
            end)
        end
    })
end

--- 显示主菜单
function MainMenu.Show()
    -- 恢复 BGM
    if bgmSource and bgmSound then
        if not bgmSource:IsPlaying() then
            bgmSource:Play(bgmSound)
        end
    end
    -- 重新检查存档状态并重建 UI
    CheckSaveData(function()
        BuildUI()
    end)
end

--- 隐藏主菜单
function MainMenu.Hide()
    UI.SetRoot(nil)
    -- 停止 BGM
    if bgmSource then
        bgmSource:Stop()
    end
end

--- 清理
function MainMenu.Cleanup()
    UI.SetRoot(nil)
    if bgmSource then
        bgmSource:Stop()
    end
    if audioScene then
        audioScene:Dispose()
        audioScene = nil
    end
    audioNode = nil
    clickSource = nil
    clickSound = nil
    bgmSource = nil
    bgmSound = nil
    initialized = false
end

return MainMenu
