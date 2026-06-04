------------------------------------------------------------
-- editor/play/FragilePlatform.lua — 脆弱平台系统
------------------------------------------------------------
local FragilePlatform = {}

function FragilePlatform.Attach(M)

    local C = require("editor.Constants")
    local S = require("editor.State")
    local TileUtils = require("editor.TileUtils")

    --- 碎裂音效用独立 Scene 承载
    local fragileAudioScene = nil

    --- 洪水填充：返回与起始格相连通的所有脆弱格子（set of "row_col" keys）
    local function FloodFillFragile(startRow, startCol)
        local visited = {}
        local queue = { { startRow, startCol } }
        visited[startRow .. "_" .. startCol] = true
        local idx = 1
        while idx <= #queue do
            local r, c = queue[idx][1], queue[idx][2]
            idx = idx + 1
            local neighbors = { {r-1, c}, {r+1, c}, {r, c-1}, {r, c+1} }
            for _, nb in ipairs(neighbors) do
                local nr, nc = nb[1], nb[2]
                local key = nr .. "_" .. nc
                if nr >= 1 and nr <= S.MAP_ROWS and nc >= 1 and nc <= S.MAP_COLS
                   and not visited[key] and not S.play.fragileGone[key] then
                    local val = S.levelData[nr][nc]
                    if val and TileUtils.GetTileType(val) == C.TILE.FRAGILE then
                        visited[key] = true
                        queue[#queue + 1] = { nr, nc }
                    end
                end
            end
        end
        return visited
    end

    --- 获取玩家脚下的脆弱平台连通集合（如果站在脆弱格子上）
    local function GetFragilePlatformUnderFeet()
        if not S.play.isOnGround then return nil end
        local s = M.PlayerGridSize()
        local feetRow = S.play.gridY + s
        for dx = 0, s - 1 do
            local col = S.play.gridX + dx
            if col >= 1 and col <= S.MAP_COLS and feetRow >= 1 and feetRow <= S.MAP_ROWS then
                local val = S.levelData[feetRow][col]
                if val then
                    local base = TileUtils.GetTileType(val)
                    local key = feetRow .. "_" .. col
                    if base == C.TILE.FRAGILE and not S.play.fragileGone[key] then
                        return FloodFillFragile(feetRow, col)
                    end
                end
            end
        end
        return nil
    end

    --- 播放碎裂音效
    local function PlayFragileCrumbleSound()
        local sound = cache:GetResource("Sound", "audio/sfx/fragile_crumble.ogg")
        if not sound then return end
        sound.looped = false
        if not fragileAudioScene then
            fragileAudioScene = Scene()
            fragileAudioScene:CreateComponent("Octree")
        end
        local node = fragileAudioScene:CreateChild("FragileSfx")
        local src = node:CreateComponent("SoundSource")
        src.soundType = "Effect"
        src:Play(sound)
        src.autoRemoveMode = REMOVE_NODE
    end

    --- 销毁一个脆弱平台（生成碎裂粒子）
    local function DestroyFragilePlatform(platformSet)
        PlayFragileCrumbleSound()
        for key, _ in pairs(platformSet) do
            S.play.fragileGone[key] = true
            local sep = key:find("_")
            local row = tonumber(key:sub(1, sep - 1))
            local col = tonumber(key:sub(sep + 1))
            local cx = (col - 1) * C.GRID + C.GRID * 0.5
            local cy = (row - 1) * C.GRID + C.GRID * 0.5
            for _ = 1, 6 do
                table.insert(S.play.fragileParticles, {
                    x = cx + (math.random() - 0.5) * C.GRID * 0.6,
                    y = cy + (math.random() - 0.5) * C.GRID * 0.6,
                    vx = (math.random() - 0.5) * 80,
                    vy = -(30 + math.random() * 50),
                    size = 1.5 + math.random() * 2.0,
                    life = 0.6 + math.random() * 0.4,
                    maxLife = 1.0,
                    gravity = 200 + math.random() * 60,
                    rot = math.random() * 6.28,
                    rotSpeed = (math.random() - 0.5) * 8,
                })
            end
        end
    end

    --- 每帧检测脆弱平台状态（站上后离开即触发销毁）
    function M.UpdateFragilePlatform(dt)
        -- 更新粒子
        local i = 1
        while i <= #S.play.fragileParticles do
            local p = S.play.fragileParticles[i]
            p.life = p.life - dt
            if p.life <= 0 then
                table.remove(S.play.fragileParticles, i)
            else
                p.vy = p.vy + p.gravity * dt
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                p.rot = p.rot + p.rotSpeed * dt
                i = i + 1
            end
        end

        -- 检测玩家脚下脆弱平台
        local currentPlatform = GetFragilePlatformUnderFeet()

        if S.play.fragilePrevPlatform and not currentPlatform then
            -- 玩家离开了之前站的脆弱平台 → 销毁它
            DestroyFragilePlatform(S.play.fragilePrevPlatform)
            S.play.fragilePrevPlatform = nil
        elseif S.play.fragilePrevPlatform and currentPlatform then
            -- 检查是否还在同一个平台上（通过判断是否有交集）
            local sameplatform = false
            for key, _ in pairs(currentPlatform) do
                if S.play.fragilePrevPlatform[key] then
                    sameplatform = true
                    break
                end
            end
            if not sameplatform then
                -- 离开旧平台跳到了新平台 → 销毁旧平台
                DestroyFragilePlatform(S.play.fragilePrevPlatform)
            end
            S.play.fragilePrevPlatform = currentPlatform
        else
            S.play.fragilePrevPlatform = currentPlatform
        end
    end

    --- 绘制脆弱平台碎裂粒子
    function M.DrawFragileParticles(vg)
        for _, p in ipairs(S.play.fragileParticles) do
            local alpha = math.floor(255 * (p.life / p.maxLife))
            local px = p.x - S.playCameraX
            local py = p.y - S.playCameraY
            nvgSave(vg)
            nvgTranslate(vg, px, py)
            nvgRotate(vg, p.rot)
            nvgBeginPath(vg)
            nvgRect(vg, -p.size * 0.5, -p.size * 0.5, p.size, p.size)
            nvgFillColor(vg, nvgRGBA(160, 130, 80, alpha))
            nvgFill(vg)
            nvgRestore(vg)
        end
    end

end

return FragilePlatform
