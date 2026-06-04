------------------------------------------------------------
-- editor/play/Camera.lua — 相机控制
------------------------------------------------------------
local Camera = {}

function Camera.Attach(M)

    local C = require("editor.Constants")
    local S = require("editor.State")

    function M.UpdateCamera(dt)
        local zoom = S.playerParams.cameraZoom or 1.0

        -- 水平跟随
        local boundLeftPx = (S.camBound.left - 1) * C.GRID
        local boundRightPx = S.camBound.right * C.GRID
        local viewW = S.playViewW * zoom
        local camMinX = boundLeftPx
        local camMaxX = math.max(boundLeftPx, boundRightPx - viewW)
        local targetCamX = (S.play.gridX - 1) * C.GRID - viewW * 0.35
        targetCamX = math.max(camMinX, math.min(targetCamX, camMaxX))
        S.playCameraX = S.playCameraX + (targetCamX - S.playCameraX) * math.min(1, dt * 8)

        -- 垂直跟随
        local boundTopPx = (S.camBound.top - 1) * C.GRID
        local boundBottomPx = S.camBound.bottom * C.GRID
        local viewH = S.playViewH * zoom
        local camMinY = boundTopPx
        local camMaxY = math.max(boundTopPx, boundBottomPx - viewH)
        local targetCamY = (S.play.gridY - 1) * C.GRID - viewH * 0.5
        targetCamY = math.max(camMinY, math.min(targetCamY, camMaxY))
        S.playCameraY = S.playCameraY + (targetCamY - S.playCameraY) * math.min(1, dt * 8)
    end

end

return Camera
