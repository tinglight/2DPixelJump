------------------------------------------------------------
-- editor/play/DeathRespawn.lua — 死亡 / 复活系统
------------------------------------------------------------
local DeathRespawn = {}

function DeathRespawn.Attach(M)

    local C = require("editor.Constants")
    local S = require("editor.State")
    local CrossLevel = require("editor.CrossLevel")

    local CIRCLE_CLOSE_TIME = 0.6   -- 缩圈时间
    local BLACKOUT_TIME = 0.3       -- 全黑停顿时间

    -- 阶段: nil=正常, "circleClose"=缩圈, "blackout"=全黑停顿, "waitKey"=等待按键
    M.deathPhase = nil
    M.deathPhaseTimer = 0

    function M.UpdateDeathRespawn(dt)
        S.play.deathTimer = S.play.deathTimer + dt

        -- 首帧启动 deathPhase
        if M.deathPhase == nil then
            M.deathPhase = "circleClose"
            M.deathPhaseTimer = 0
        end

        M.deathPhaseTimer = M.deathPhaseTimer + dt

        if M.deathPhase == "circleClose" then
            if M.deathPhaseTimer >= CIRCLE_CLOSE_TIME then
                M.deathPhase = "blackout"
                M.deathPhaseTimer = 0
            end
        elseif M.deathPhase == "blackout" then
            if M.deathPhaseTimer >= BLACKOUT_TIME then
                M.deathPhase = "waitKey"
                M.deathPhaseTimer = 0
            end
        elseif M.deathPhase == "waitKey" then
            if input:GetKeyPress(KEY_ESCAPE) then
                M.deathPhase = nil
                M.deathPhaseTimer = 0
                M.ExitPlayMode()
                if S.editorMode == C.MODE_WORLDPLAY then
                    S.editorMode = C.MODE_WORLDMAP
                    M._worldMapEditor.SetLayout(S.screenDesignW, S.screenDesignH, C.TOPBAR_H, 0, S.sidebarOpen and C.SIDEBAR_W or 0)
                else
                    S.editorMode = C.MODE_EDIT
                end
                return
            end
            if input:GetNumTouches() > 0 or M.AnyKeyPressed() then
                M.deathPhase = nil
                M.deathPhaseTimer = 0
                M.Respawn()
            end
        end
    end

    --- 检测是否有任意键被按下（不含ESC，已在上面处理）
    function M.AnyKeyPressed()
        for i = KEY_A, KEY_Z do
            if input:GetKeyPress(i) then return true end
        end
        if input:GetKeyPress(KEY_SPACE) then return true end
        if input:GetKeyPress(KEY_RETURN) then return true end
        if input:GetMouseButtonPress(MOUSEB_LEFT) then return true end
        if input:GetMouseButtonPress(MOUSEB_RIGHT) then return true end
        return false
    end

    function M.Respawn()
        -- 检查是否有篝火存档点
        local useBonfire = false
        if S.checkpointFile and S.checkpointCol and S.checkpointRow then
            -- 世界试玩模式下，如果篝火在其他关卡，先加载该关卡
            if S.editorMode == C.MODE_WORLDPLAY and S.checkpointFile ~= S.worldPlayCurrentFile then
                if M.WorldPlayLoadLevel(S.checkpointFile, nil) then
                    CrossLevel.Clear()
                end
            end
            S.play.gridX = S.checkpointCol
            S.play.gridY = S.checkpointRow - (C.PLAYER_GRID_H - 1)
            useBonfire = true
        else
            S.play.gridX = S.spawnCol
            S.play.gridY = S.spawnRow - (C.PLAYER_GRID_H - 1)
        end

        -- 重置物理状态
        S.play.isOnGround = false
        S.play.isJumping = false
        S.play.isClimbing = false
        S.play.climbTimer = 0
        S.play.jumpGridsRemain = 0
        S.play.moveTimer = 0
        S.play.fallTimer = 0
        S.play.fallTickCurrent = C.PLAY_FALL_BASE
        S.play.jumpTimer = 0
        -- 死亡复活恢复满血，跳跃力归零
        S.play.fallGridCount = 0
        S.play.isMoving = false
        S.play.moveAnimTime = 0
        S.play.fallAnimTime = 0
        S.play.alive = true
        S.play.deathTimer = 0
        S.prevPlayLeft = false
        S.prevPlayRight = false
        S.playMoveFirst = false
        M.InitPlayPixels()
        S.tipPixels = {}
        S.tipSpawnTimer = 0
        S.playFallParticles = {}
        M.campfireParticles = {}
        M.campfireIgniteEffect = {}
        S.play.fragilePrevPlatform = nil
        S.play.fragileGone = {}
        S.play.fragileParticles = {}

        if useBonfire then
            local key = S.checkpointRow .. "_" .. S.checkpointCol
            S.checkpointActivated = {}
            S.checkpointActivated[key] = true
            M._RestoreCampfireLight()
        end

        M._fogOfWar.InitZoneVisibility(S.play.gridX + 1, S.play.gridY + 1)
        M.SnapCameraToPlayer()
    end

end

return DeathRespawn
