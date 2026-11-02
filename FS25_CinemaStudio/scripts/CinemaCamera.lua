-- Vlastní kamera editoru: rig yaw → pitch → roll → kamera (otočená o π, protože kamera GIANTS hledí podél -Z).
-- Každá osa na vlastním uzlu, takže pořadí rotací je dané stromem a neplete se s pořadím Eulerových úhlů enginu.
-- Při zapnutí skryje HUD a postavu hráče / řidiče, při vypnutí vše vrátí a aktivuje původní kameru.

CinemaCamera = CinemaCamera or {}
local C = CinemaCamera
local M = CinemaMath

C.NEAR_CLIP = 0.2
C.FAR_CLIP = 12000

function C.new()
    return { active = false, focal = 35 }
end

function C.start(cam)
    if cam.active then
        return
    end
    cam.prevCamera = g_cameraManager:getActiveCamera()
    local fov = M.focalToFov(cam.focal)
    local px, py, pz, yaw, pitch = 0, 100, 0, 0, 0
    if cam.prevCamera ~= nil and cam.prevCamera ~= 0 then
        fov = getFovY(cam.prevCamera)
        px, py, pz = getWorldTranslation(cam.prevCamera)
        -- kamera hledí podél svého -Z
        local dx, dy, dz = localDirectionToWorld(cam.prevCamera, 0, 0, -1)
        yaw, pitch = M.yawPitchFromDirection(dx, dy, dz)
    end
    cam.focal = M.clampFocal(M.fovToFocal(fov))
    cam.rig = createTransformGroup("cinemaRig")
    cam.pitchNode = createTransformGroup("cinemaPitch")
    cam.rollNode = createTransformGroup("cinemaRoll")
    cam.node = createCamera("cinemaCamera", M.focalToFov(cam.focal), C.NEAR_CLIP, C.FAR_CLIP)
    link(getRootNode(), cam.rig)
    link(cam.rig, cam.pitchNode)
    link(cam.pitchNode, cam.rollNode)
    link(cam.rollNode, cam.node)
    setRotation(cam.node, 0, math.pi, 0)
    g_cameraManager:addCamera(cam.node, nil, false)
    g_cameraManager:setActiveCamera(cam.node)
    cam.active = true
    C.setPose(cam, px, py, pz, M.quatFromYawPitchRoll(yaw, pitch, 0), cam.focal)
    C.hideScene(cam, true)
end

function C.stop(cam)
    if not cam.active then
        return
    end
    C.hideScene(cam, false)
    local prev = cam.prevCamera
    if prev == nil or prev == 0 or not entityExists(prev) then
        prev = nil
        pcall(function() prev = g_localPlayer:getCurrentCameraNode() end)
    end
    if prev ~= nil then
        g_cameraManager:setActiveCamera(prev)
    end
    g_cameraManager:removeCamera(cam.node)
    delete(cam.rig)
    cam.rig, cam.pitchNode, cam.rollNode, cam.node = nil, nil, nil, nil
    cam.prevCamera = nil
    cam.active = false
end

function C.setPose(cam, x, y, z, q, focal)
    if not cam.active then
        return
    end
    local yaw, pitch, roll = M.quatToYawPitchRoll(q)
    setWorldTranslation(cam.rig, x, y, z)
    setRotation(cam.rig, 0, yaw, 0)
    setRotation(cam.pitchNode, pitch, 0, 0)
    setRotation(cam.rollNode, 0, 0, roll)
    cam.x, cam.y, cam.z = x, y, z
    cam.yaw, cam.pitch, cam.roll = yaw, pitch, roll
    if focal ~= nil and focal ~= cam.appliedFocal then
        cam.appliedFocal = focal
        setFovY(cam.node, M.focalToFov(focal))
    end
    cam.focal = focal or cam.focal
end

-- Bod ve světě → obrazovka; nil, když je za kamerou.
function C.worldToScreen(cam, x, y, z)
    if not cam.active then
        return nil
    end
    local _, _, lz = worldToLocal(cam.node, x, y, z)
    if lz > -C.NEAR_CLIP then
        return nil
    end
    local sx, sy = project(x, y, z)
    return sx, sy, -lz
end

function C.hideScene(cam, hide)
    local hud = g_currentMission ~= nil and g_currentMission.hud or nil
    if hud ~= nil then
        if hide then
            cam.hudWasVisible = hud.getIsVisible == nil or hud:getIsVisible()
            hud:setIsVisible(false)
        elseif cam.hudWasVisible ~= nil then
            hud:setIsVisible(cam.hudWasVisible)
            cam.hudWasVisible = nil
        end
    end
    local player = g_localPlayer
    if player == nil then
        return
    end
    if hide then
        local vehicle = player:getCurrentVehicle()
        if vehicle ~= nil and vehicle.deleteVehicleCharacter ~= nil then
            vehicle:deleteVehicleCharacter()
            cam.charVehicle = vehicle
        elseif player.graphicsComponent ~= nil and not (player.camera ~= nil and player.camera.isFirstPerson) then
            -- v první osobě je model skrytý už teď (vzor ConstructionScreen)
            player.graphicsComponent:setModelVisibility(false)
            cam.hidModel = true
        end
    else
        if cam.charVehicle ~= nil then
            if not cam.charVehicle.isDeleted then
                cam.charVehicle:restoreVehicleCharacter()
            end
            cam.charVehicle = nil
        end
        if cam.hidModel then
            player.graphicsComponent:setModelVisibility(true)
            cam.hidModel = nil
        end
        if CinemaPerson ~= nil then
            CinemaPerson.release()
        end
        if CinemaProps ~= nil then
            CinemaProps.releaseRiders()
        end
    end
end
