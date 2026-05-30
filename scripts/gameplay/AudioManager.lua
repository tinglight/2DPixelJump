------------------------------------------------------------
-- gameplay/AudioManager.lua — 音频管理（背景音乐 + 音效）
------------------------------------------------------------
-- 使用持久 SoundSource 模式（与 PipeSystem 一致）。
-- 每种音效对应一个固定 SoundSource，调 Play() 触发。
------------------------------------------------------------

local M = {}

---@type Scene
local audioScene = nil
---@type Node
local musicNode = nil
---@type SoundSource
local musicSource = nil

-- 音效 SoundSource 池（每种音效一个持久 Source）
---@type table<string, SoundSource>
local sfxSources = {}
-- 音效 Sound 资源缓存
---@type table<string, Sound>
local soundCache = {}

-- 音量配置
M.musicVolume = 0.25
M.sfxVolume = 1.0

-- 是否已初始化
local initialized = false

-- ====================================================================
-- 初始化
-- ====================================================================

function M.Init()
    if initialized then return end

    -- 创建独立 Scene 承载音频组件（与 PipeSystem 一致的模式）
    audioScene = Scene()
    audioScene:CreateComponent("Octree")

    -- 背景音乐节点 + 持久 SoundSource
    musicNode = audioScene:CreateChild("Music")
    musicSource = musicNode:CreateComponent("SoundSource")
    musicSource.soundType = "Music"
    musicSource.gain = M.musicVolume

    -- 预加载音效资源
    soundCache.jump = cache:GetResource("Sound", "audio/sfx/jump.ogg")
    soundCache.death = cache:GetResource("Sound", "audio/sfx/death.ogg")
    soundCache.save = cache:GetResource("Sound", "audio/sfx/save.ogg")

    local climbSound = cache:GetResource("Sound", "audio/sfx/ladder_climb.ogg")
    if climbSound then
        soundCache.climb = climbSound
    end

    -- 为每种音效创建持久 SoundSource（不依赖 autoRemoveMode）
    local sfxNode = audioScene:CreateChild("SFX")
    for name, _ in pairs(soundCache) do
        local source = sfxNode:CreateComponent("SoundSource")
        source.soundType = "Effect"
        source.gain = M.sfxVolume
        sfxSources[name] = source
    end

    -- 打印调试信息
    for name, snd in pairs(soundCache) do
        print("[AudioManager] Loaded SFX: " .. name .. " len=" .. string.format("%.2f", snd.length) .. "s")
    end

    -- 加载并播放背景音乐（循环）
    local bgm = cache:GetResource("Sound", "audio/music_1780135955014.ogg")
    if bgm then
        bgm.looped = true
        musicSource:Play(bgm)
        print("[AudioManager] BGM started, length=" .. string.format("%.1f", bgm.length) .. "s")
    else
        print("[AudioManager] WARNING: BGM file not found!")
    end

    -- 确保主音量不是静音
    audio:SetMasterGain("Effect", 1.0)
    audio:SetMasterGain("Music", 1.0)
    audio:SetMasterGain("Master", 1.0)

    initialized = true
    print("[AudioManager] Init OK, sfx count=" .. tostring(M.CountTable(sfxSources)))
end

-- ====================================================================
-- 音效播放
-- ====================================================================

--- 播放一次性音效（使用持久 SoundSource，直接 Play 覆盖）
---@param name string 音效名称: "jump" | "death" | "save" | "climb"
function M.PlaySFX(name)
    if not initialized then return end

    local source = sfxSources[name]
    local sound = soundCache[name]
    if not source or not sound then
        print("[AudioManager] PlaySFX failed: " .. tostring(name))
        return
    end

    source.gain = M.sfxVolume
    source:Play(sound)
end

-- ====================================================================
-- 控制接口
-- ====================================================================

function M.PauseMusic()
    if musicSource then
        musicSource:Stop()
    end
end

function M.ResumeMusic()
    if musicSource and not musicSource:IsPlaying() then
        local bgm = cache:GetResource("Sound", "audio/music_1780135955014.ogg")
        if bgm then
            bgm.looped = true
            musicSource:Play(bgm)
        end
    end
end

function M.SetMusicVolume(vol)
    M.musicVolume = vol
    if musicSource then
        musicSource.gain = vol
    end
end

function M.SetSFXVolume(vol)
    M.sfxVolume = vol
    for _, source in pairs(sfxSources) do
        source.gain = vol
    end
end

function M.IsInitialized()
    return initialized
end

-- ====================================================================
-- 工具
-- ====================================================================

function M.CountTable(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ====================================================================
-- 清理
-- ====================================================================

function M.Cleanup()
    if musicSource then
        musicSource:Stop()
    end
    if audioScene then
        audioScene:Dispose()
        audioScene = nil
    end
    musicNode = nil
    musicSource = nil
    sfxSources = {}
    soundCache = {}
    initialized = false
end

return M
