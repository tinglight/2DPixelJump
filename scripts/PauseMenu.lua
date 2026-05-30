------------------------------------------------------------
-- PauseMenu.lua — 游戏内暂停菜单
------------------------------------------------------------
-- ESC 调出/收起，暂停游戏逻辑
-- 提供：继续游戏、设置、回到主菜单、退出游戏
------------------------------------------------------------

local UI = require("urhox-libs/UI")

local PauseMenu = {}

-- ====================================================================
-- 状态
-- ====================================================================
local isOpen = false
local isPaused = false

-- UI 引用
---@type Modal
local settingsModal = nil
---@type Modal
local backToMenuModal = nil
---@type Modal
local exitModal = nil
---@type any
local pauseRoot = nil

-- 音效
---@type Sound
local clickSound = nil
---@type SoundSource
local clickSource = nil
---@type Node
local audioNode = nil
---@type Scene
local audioScene = nil

-- 音量设置（与主菜单共享状态）
local musicVolume = 0.25
local sfxVolume = 1.0
local musicMuted = false
local sfxMuted = false

-- 回调
local onResume = nil          -- 继续游戏
local onBackToMenu = nil      -- 回到主菜单
local onOpenEditor = nil      -- 打开编辑器

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
-- UI 构建
-- ====================================================================

local function BuildUI()
    -- 按钮通用样式
    local btnWidth = 200
    local btnHeight = 44
    local btnFontSize = 16

    local btnBg = { 30, 30, 30, 200 }
    local btnBgHover = { 60, 50, 40, 220 }
    local btnBgPressed = { 80, 60, 30, 240 }
    local btnTextColor = { 220, 200, 170, 255 }
    local btnBorderColor = { 120, 100, 70, 180 }

    local function MenuButton(props)
        return UI.Button {
            text = props.text,
            width = btnWidth,
            height = btnHeight,
            fontSize = btnFontSize,
            textColor = btnTextColor,
            backgroundColor = btnBg,
            hoverBackgroundColor = btnBgHover,
            pressedBackgroundColor = btnBgPressed,
            borderWidth = 1,
            borderColor = btnBorderColor,
            borderRadius = 4,
            onClick = function(self)
                PlayClickSound()
                if props.onClick then props.onClick(self) end
            end
        }
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
    -- 返回主菜单确认弹窗
    -- ============================================================
    backToMenuModal = UI.Modal {
        title = "返回主菜单",
        isOpen = false,
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = false,
        children = {
            UI.Label {
                text = "返回主菜单将重置到上一个存档点，确定继续吗？",
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
                            backToMenuModal:Close()
                            PauseMenu.Close()
                            if onBackToMenu then onBackToMenu() end
                        end
                    },
                    UI.Button {
                        text = "返回",
                        width = 80, height = 36, fontSize = 13,
                        backgroundColor = { 50, 50, 50, 200 },
                        hoverBackgroundColor = { 70, 70, 70, 220 },
                        pressedBackgroundColor = { 90, 90, 90, 240 },
                        textColor = btnTextColor,
                        borderRadius = 4,
                        onClick = function(self)
                            PlayClickSound()
                            backToMenuModal:Close()
                        end
                    },
                }
            }
        }
    }

    -- ============================================================
    -- 退出游戏确认弹窗
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
                        textColor = btnTextColor,
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
            PauseMenu.Close()
            if onOpenEditor then onOpenEditor() end
        end
    }

    -- ============================================================
    -- 暂停菜单根布局
    -- ============================================================
    pauseRoot = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            -- 按钮容器
            UI.Panel {
                alignItems = "center",
                gap = 12,
                padding = 24,
                backgroundColor = { 10, 10, 10, 180 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = { 80, 70, 50, 100 },
                children = {
                    -- 继续游戏
                    MenuButton {
                        text = "继续游戏",
                        onClick = function(self)
                            PauseMenu.Close()
                        end
                    },
                    -- 设置
                    MenuButton {
                        text = "设置",
                        onClick = function(self)
                            settingsModal:Open()
                        end
                    },
                    -- 回到主菜单
                    MenuButton {
                        text = "回到主菜单",
                        onClick = function(self)
                            backToMenuModal:Open()
                        end
                    },
                    -- 退出游戏
                    MenuButton {
                        text = "退出游戏",
                        onClick = function(self)
                            exitModal:Open()
                        end
                    },
                }
            },

            -- 编辑器按钮（右上角）
            editorBtn,

            -- 弹窗层
            settingsModal,
            backToMenuModal,
            exitModal,
        }
    }
end

-- ====================================================================
-- 公共接口
-- ====================================================================

--- 初始化暂停菜单（在游戏开始时调用一次）
---@param callbacks table { onResume, onBackToMenu, onOpenEditor }
function PauseMenu.Init(callbacks)
    onResume = callbacks.onResume
    onBackToMenu = callbacks.onBackToMenu
    onOpenEditor = callbacks.onOpenEditor

    -- 初始化音效（复用已有的 UI 系统，不重新 Init）
    if not audioScene then
        audioScene = Scene()
        audioScene:CreateComponent("Octree")
        audioNode = audioScene:CreateChild("PauseMenuAudio")
        clickSource = audioNode:CreateComponent("SoundSource")
        clickSource.soundType = "Effect"
        clickSource.gain = sfxVolume
        clickSound = cache:GetResource("Sound", "audio/sfx/ui_click.ogg")
    end

    BuildUI()
    print("[PauseMenu] Init OK")
end

--- 打开暂停菜单
function PauseMenu.Open()
    if isOpen then return end
    isOpen = true
    isPaused = true
    UI.SetRoot(pauseRoot)
end

--- 关闭暂停菜单
function PauseMenu.Close()
    if not isOpen then return end
    isOpen = false
    isPaused = false
    -- 恢复为编辑器的空 root（让 NanoVG 渲染接管）
    UI.SetRoot(UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "none",
    })
    if onResume then onResume() end
end

--- 直接回到主菜单（F3 快捷键调用）
function PauseMenu.BackToMenu()
    isOpen = false
    isPaused = false
    if onBackToMenu then onBackToMenu() end
end

--- 切换暂停菜单
function PauseMenu.Toggle()
    if isOpen then
        PauseMenu.Close()
    else
        PauseMenu.Open()
    end
end

--- 是否处于暂停状态
---@return boolean
function PauseMenu.IsPaused()
    return isPaused
end

--- 是否已打开
---@return boolean
function PauseMenu.IsOpen()
    return isOpen
end

--- 清理
function PauseMenu.Cleanup()
    isOpen = false
    isPaused = false
    if audioScene then
        audioScene:Dispose()
        audioScene = nil
    end
    audioNode = nil
    clickSource = nil
    clickSound = nil
    pauseRoot = nil
    settingsModal = nil
    backToMenuModal = nil
    exitModal = nil
end

return PauseMenu
