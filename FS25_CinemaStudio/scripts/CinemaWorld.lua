-- Herní svět pro editor: vozidla (hledání podle uniqueId, název, obrys na obrazovce, poloha a směr), klik do terénu,
-- a herci: zapamatování startu soupravy, návrat na start (postup vanilla FSBaseMission:teleportVehicle) a jízda
-- po trase přes AIVehicleUtil.driveToPoint bez AI zaměstnance (vzor couvání ze SprayDroneCinema).

CinemaWorld = CinemaWorld or {}
local W = CinemaWorld
local M = CinemaMath
local R = CinemaRoute
local Cam = CinemaCamera

W.PICK_DISTANCE = 450
W.PICK_LIMIT = 60

function W.terrainY(x, z)
    return getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
end

function W.vehicles()
    local system = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    return system ~= nil and system.vehicles or {}
end

function W.uid(v)
    if v.getUniqueId ~= nil then
        return v:getUniqueId()
    end
    return v.uniqueId
end

local function usable(v)
    return v ~= nil and not v.isDeleted and v.rootNode ~= nil and v.rootNode ~= 0 and entityExists(v.rootNode)
end

W.RIDE_LIFT = 0.4 -- m; tolik nad terénem musí předmět být, aby neležel na zemi vedle vozidla
W.RIDE_MARGIN = 0.15 -- m; o kolik smí střed předmětu přesahovat obrys vozidla

-- Vozidlo, na kterém leží předmět se středem x, y, z a půdorysem area (m²): korba pickupu, vlek, návěs. Střed je nad obrysem
-- vozidla aspoň dvakrát většího a výš nad terénem, než leží věci na zemi vedle něj; z více takových nejmenší. own = vozidlo
-- předmětu (samo sebe nevozí); nil, když předmět leží na zemi nebo mimo obrys.
function W.carrierAt(own, x, y, z, area)
    if y - W.terrainY(x, z) < W.RIDE_LIFT then
        return nil
    end
    local best, bestArea = nil, nil
    for _, c in ipairs(W.vehicles()) do
        local size = c ~= own and usable(c) and c.size or nil
        local a = size ~= nil and (size.width or 0) * (size.length or 0) or 0
        if a > area * 2 then
            local lx, _, lz = worldToLocal(c.rootNode, x, y, z)
            if math.abs(lx - (size.widthOffset or 0)) <= size.width * 0.5 + W.RIDE_MARGIN
                and math.abs(lz - (size.lengthOffset or 0)) <= size.length * 0.5 + W.RIDE_MARGIN
                and (bestArea == nil or a < bestArea) then
                best, bestArea = c, a
            end
        end
    end
    return best
end

-- Poloha předmětu na vozidle: x, y, z a otočení kolem svislé osy podle vozidla; nil, když vozidlo ve světě není.
-- rider = { rider = uid, lx, ly, lz, lry } (souřadnice předmětu ve vozidle a natočení proti němu).
function W.ridePose(rider)
    local carrier = rider.rider ~= nil and W.find(rider.rider) or nil
    if carrier == nil then
        return nil
    end
    local x, y, z = localToWorld(carrier.rootNode, rider.lx or 0, rider.ly or 0, rider.lz or 0)
    local _, cry = getWorldRotation(carrier.rootNode)
    return x, y, z, cry + (rider.lry or 0)
end

-- Zapíše do t vozidlo, na kterém předmět s uzlem node leží (rider, lx, ly, lz, lry), nebo pole smaže.
function W.captureRider(t, own, node, area)
    t.rider, t.lx, t.ly, t.lz, t.lry = nil, nil, nil, nil, nil
    local x, y, z = getWorldTranslation(node)
    local carrier = W.carrierAt(own, x, y, z, area)
    if carrier ~= nil then
        local _, ry = getWorldRotation(node)
        local _, cry = getWorldRotation(carrier.rootNode)
        t.rider = W.uid(carrier)
        t.lx, t.ly, t.lz = worldToLocal(carrier.rootNode, x, y, z)
        t.lry = ry - cry
    end
end

W.cache = {}

function W.find(uid)
    if uid == nil then
        return nil
    end
    local v = W.cache[uid]
    if usable(v) and W.uid(v) == uid then
        return v
    end
    W.cache[uid] = nil
    for _, other in ipairs(W.vehicles()) do
        if usable(other) and W.uid(other) == uid then
            W.cache[uid] = other
            return other
        end
    end
    return nil
end

function W.name(v)
    if v == nil then
        return "?"
    end
    if v.getFullName ~= nil then
        local ok, name = pcall(v.getFullName, v)
        if ok and name ~= nil then
            return name
        end
    end
    return tostring(v.typeName or v.configFileName or "?")
end

-- Poloha (střed na zemi) a směr jízdy vozidla.
function W.state(v)
    local x, y, z = getWorldTranslation(v.rootNode)
    local dx, _, dz = localDirectionToWorld(v.rootNode, 0, 0, 1)
    return { x = x, y = y, z = z, heading = math.atan2(dx, dz) }
end

-- Drony vleku SprayDrone (jsou součástí vleku, ne vozidla): { k, node } pro každý dron, který má uzel.
function W.drones(v)
    local env = _G["FS25_SprayDroneTrailer"]
    local station = env ~= nil and env.SprayDroneStation or nil
    local api = env ~= nil and env.SprayDroneDrones or nil
    local list = {}
    if v == nil or station == nil or api == nil or v[station.SPEC_NAME] == nil then
        return list
    end
    for k = 1, api.getCount(v) do
        local spec = api.getSpec(v, k)
        if spec ~= nil and spec.node ~= nil then
            list[#list + 1] = { k = k, node = spec.node }
        end
    end
    return list
end

W.DRONE_TARGET = "drone:"

function W.droneTarget(v, k)
    return string.format("%s%s:%d", W.DRONE_TARGET, W.uid(v), k)
end

-- Cíl dronu → vlek a uzel dronu, nebo nil.
function W.droneOf(target)
    if type(target) ~= "string" or target:sub(1, #W.DRONE_TARGET) ~= W.DRONE_TARGET then
        return nil
    end
    local uid, k = target:sub(#W.DRONE_TARGET + 1):match("^(.+):(%d+)$")
    local v = uid ~= nil and W.find(uid) or nil
    for _, d in ipairs(W.drones(v)) do
        if d.k == tonumber(k) then
            return v, d.node, d.k
        end
    end
    return nil
end

function W.nodeState(node)
    local x, y, z = getWorldTranslation(node)
    local dx, _, dz = localDirectionToWorld(node, 0, 0, 1)
    return { x = x, y = y, z = z, heading = math.atan2(dx, dz) }
end

local function boxCorners(v)
    local size = v.size or {}
    local w, l, h = size.width or 3, size.length or 5, size.height or 3
    local wo, lo, ho = size.widthOffset or 0, size.lengthOffset or 0, size.heightOffset or 0
    local corners = {}
    for _, sx in ipairs({ -0.5, 0.5 }) do
        for _, sz in ipairs({ -0.5, 0.5 }) do
            for _, sy in ipairs({ 0, 1 }) do
                corners[#corners + 1] = { localToWorld(v.rootNode, sx * w + wo, ho + sy * h, sz * l + lo) }
            end
        end
    end
    return corners
end

-- Obdélník vozidla na obrazovce (x0, y0, x1, y1); nil, když je některý roh za kamerou.
function W.screenBox(cam, v)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, c in ipairs(boxCorners(v)) do
        local sx, sy = Cam.worldToScreen(cam, c[1], c[2], c[3])
        if sx == nil then
            return nil
        end
        x0, y0, x1, y1 = math.min(x0, sx), math.min(y0, sy), math.max(x1, sx), math.max(y1, sy)
    end
    if x1 < 0 or y1 < 0 or x0 > 1 or y0 > 1 then
        return nil
    end
    return x0, y0, x1, y1
end

-- Vozidla v dosahu kamery s obrysem na obrazovce, nejbližší první.
function W.candidates(cam)
    local list = {}
    for _, v in ipairs(W.vehicles()) do
        if usable(v) and W.uid(v) ~= nil then
            local x, y, z = getWorldTranslation(v.rootNode)
            local d = math.sqrt((x - cam.x) ^ 2 + (y - cam.y) ^ 2 + (z - cam.z) ^ 2)
            if d <= W.PICK_DISTANCE then
                local x0, y0, x1, y1 = W.screenBox(cam, v)
                if x0 ~= nil then
                    list[#list + 1] = { vehicle = v, dist = d, box = { x0, y0, x1, y1 } }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    while #list > W.PICK_LIMIT do
        table.remove(list)
    end
    return list
end

-- Kandidát pod kurzorem: nejmenší obrys, který kurzor obsahuje (vlek před tahačem, nářadí před soupravou).
function W.candidateAt(list, mx, my)
    local best, bestArea = nil, math.huge
    for _, c in ipairs(list) do
        local b = c.box
        if mx >= b[1] and mx <= b[3] and my >= b[2] and my <= b[4] then
            local area = (b[3] - b[1]) * (b[4] - b[2])
            if area < bestArea then
                best, bestArea = c, area
            end
        end
    end
    return best
end

-- Bod terénu pod kurzorem.
function W.pickTerrain(cam, mx, my)
    if not cam.active then
        return nil
    end
    local ox, oy, oz, dx, dy, dz = RaycastUtil.getCameraPickingRay(mx, my, cam.node)
    if ox == nil then
        return nil
    end
    return M.rayTerrain(ox, oy, oz, dx, dy, dz, W.terrainY)
end

-- Místo pod kurzorem z pohledu kamery: první podlaha, silnice, budova nebo terén, na který paprsek narazí (v budově podlaha,
-- ne terén pod ní); vozidla a volné předměty paprsek nevidí. x, y, z, nebo nil.
function W.pickGround(cam, mx, my)
    if not cam.active then
        return nil
    end
    local ox, oy, oz, dx, dy, dz = RaycastUtil.getCameraPickingRay(mx, my, cam.node)
    if ox == nil then
        return nil
    end
    W.groundHit = nil
    if raycastClosest ~= nil and CollisionFlag ~= nil then
        local mask = (CollisionFlag.TERRAIN or 0) + (CollisionFlag.STATIC_OBJECT or 0) + (CollisionFlag.ROAD or 0) + (CollisionFlag.BUILDING or 0)
        pcall(raycastClosest, ox, oy, oz, dx, dy, dz, W.PICK_DISTANCE, "onGroundPick", W, mask)
    end
    local hit = W.groundHit
    W.groundHit = nil
    if hit ~= nil then
        return hit[1], hit[2], hit[3]
    end
    return M.rayTerrain(ox, oy, oz, dx, dy, dz, W.terrainY)
end

function W:onGroundPick(hitObjectId, x, y, z)
    if hitObjectId ~= 0 then
        W.groundHit = { x, y, z, hitObjectId }
    end
end

-- Paprsek na terén, podlahy, cesty a budovy (ne vozidla): y zásahu, id, x, z; nil, když nic.
function W.raycastAny(ox, oy, oz, dx, dy, dz, dist)
    W.groundHit = nil
    if raycastClosest ~= nil and CollisionFlag ~= nil then
        local mask = (CollisionFlag.TERRAIN or 0) + (CollisionFlag.STATIC_OBJECT or 0) + (CollisionFlag.ROAD or 0) + (CollisionFlag.BUILDING or 0)
        pcall(raycastClosest, ox, oy, oz, dx, dy, dz, dist, "onGroundPick", W, mask)
    end
    local hit = W.groundHit
    W.groundHit = nil
    if hit == nil then
        return nil
    end
    return hit[2], hit[4], hit[1], hit[3]
end

-- Tvar (ne terén) zasažený paprskem z ox, oy, oz směrem dx, dy, dz do vzdálenosti dist: id, x, y, z; nil, když nic.
function W.raycastShape(ox, oy, oz, dx, dy, dz, dist)
    W.groundHit = nil
    if raycastClosest ~= nil and CollisionFlag ~= nil then
        local mask = (CollisionFlag.STATIC_OBJECT or 0) + (CollisionFlag.BUILDING or 0) + (CollisionFlag.ROAD or 0)
        pcall(raycastClosest, ox, oy, oz, dx, dy, dz, dist, "onGroundPick", W, mask)
    end
    local hit = W.groundHit
    W.groundHit = nil
    if hit == nil or hit[4] == g_terrainNode then
        return nil
    end
    return hit[4], hit[1], hit[2], hit[3]
end

---------------------------------------------------------------------------------------------------
-- kamera připevněná na vozidlo: rám uzlu, cesta k části vozidla a kamery vozidla

-- Poloha a osy uzlu ve světě: { x, y, z, ax, ay, az }.
function W.frame(node)
    local x, y, z = getWorldTranslation(node)
    return { x = x, y = y, z = z, ax = { localDirectionToWorld(node, 1, 0, 0) }, ay = { localDirectionToWorld(node, 0, 1, 0) },
        az = { localDirectionToWorld(node, 0, 0, 1) } }
end

local function components(v)
    return v.components ~= nil and #v.components > 0 and v.components or { { node = v.rootNode } }
end

-- Cesta k uzlu vozidla, která přežije nové načtení: „c<komponenta>/<index dítěte>/…“; nil, když uzel k vozidlu nepatří.
function W.nodePath(v, node)
    local comps = components(v)
    local indices = {}
    local current = node
    for _ = 1, 64 do
        for ci, c in ipairs(comps) do
            if c.node == current then
                local parts = { "c" .. ci }
                for k = #indices, 1, -1 do
                    parts[#parts + 1] = tostring(indices[k])
                end
                return table.concat(parts, "/")
            end
        end
        local parent = getParent(current)
        if parent == nil or parent == 0 then
            return nil
        end
        indices[#indices + 1] = getChildIndex(current)
        current = parent
    end
    return nil
end

function W.nodeAt(v, path)
    local ci = type(path) == "string" and tonumber(path:match("^c(%d+)")) or nil
    local comp = ci ~= nil and components(v)[ci] or nil
    if comp == nil then
        return nil
    end
    local node = comp.node
    for index in path:gmatch("/(%d+)") do
        index = tonumber(index)
        if node == nil or index >= getNumOfChildren(node) then
            return nil
        end
        node = getChildAt(node, index)
    end
    return node
end

-- Kamery vozidla (kabina i venkovní): { node, inside }.
function W.vehicleCameras(v)
    local list = {}
    local spec = v ~= nil and v.spec_enterable or nil
    for _, camera in ipairs(spec ~= nil and spec.cameras or {}) do
        if camera.cameraNode ~= nil and camera.cameraNode ~= 0 then
            list[#list + 1] = { node = camera.cameraNode, inside = camera.isInside == true, object = camera }
        end
    end
    return list
end

-- Rám kamery vozidla (osy jako W.frame). Venkovní kameru s oddělenou polohou hra staví jen dokud je aktivní, neaktivní má
-- uzel na staré poloze někde ve světě, proto se její výchozí pohled (výchozí natočení a vzdálenost) spočítá z uzlů vozidla.
function W.vehicleCameraFrame(camera)
    local c = camera.object
    if c == nil or c.isActivated or c.rotateNode == nil or c.rotateNode == c.cameraPositionNode or c.cameraPositionNode == nil
        or c.origRotX == nil or c.origTransX == nil or c.updateRotateNodeRotation == nil then
        return W.frame(camera.node)
    end
    c.rotX, c.rotY, c.rotZ = c.origRotX, c.origRotY, c.origRotZ
    c:updateRotateNodeRotation()
    setTranslation(c.cameraPositionNode, c.origTransX, c.origTransY, c.origTransZ)
    local lx, ly, lz = getWorldTranslation(c.rotateNode)
    local px, py, pz = getWorldTranslation(c.cameraPositionNode)
    local dx, dy, dz = px - lx, py - ly, pz - lz
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    local horizontal = math.sqrt(dx * dx + dz * dz)
    if len < 1e-3 or horizontal < 1e-3 then
        return W.frame(camera.node)
    end
    local azx, azy, azz = dx / len, dy / len, dz / len
    -- ax = nahoru (svět Y) × az
    local axx, axz = azz * len / horizontal, -azx * len / horizontal
    local ayx, ayy, ayz = azy * axz, azz * axx - azx * axz, -azy * axx
    return { x = px, y = py, z = pz, ax = { axx, 0, axz }, ay = { ayx, ayy, ayz }, az = { azx, azy, azz } }
end

-- Část vozidla v, na kterou míří paprsek (uzel tvaru), nebo nil.
function W.raycastVehicle(v, ox, oy, oz, dx, dy, dz, dist)
    local flag = CollisionFlag ~= nil and CollisionFlag.VEHICLE or nil
    if raycastClosest == nil or flag == nil then
        return nil
    end
    W.groundHit = nil
    pcall(raycastClosest, ox, oy, oz, dx, dy, dz, dist, "onGroundPick", W, flag)
    local hit = W.groundHit
    W.groundHit = nil
    if hit == nil or W.nodePath(v, hit[4]) == nil then
        return nil
    end
    return hit[4]
end

-- Tvar pod kurzorem (předmět mapy), nil u terénu nebo když nic.
function W.pickShape(cam, mx, my)
    if not cam.active then
        return nil
    end
    local ox, oy, oz, dx, dy, dz = RaycastUtil.getCameraPickingRay(mx, my, cam.node)
    if ox == nil then
        return nil
    end
    return W.raycastShape(ox, oy, oz, dx, dy, dz, W.PICK_DISTANCE)
end

---------------------------------------------------------------------------------------------------
-- herci: start soupravy a návrat na něj

local function collectCombination(root)
    local vehicles, joints = {}, {}
    local function visit(v)
        vehicles[#vehicles + 1] = v
        if v.getAttachedImplements ~= nil then
            for _, implement in ipairs(v:getAttachedImplements()) do
                local object = implement.object
                if object ~= nil and not (object.getIsAdditionalAttachment ~= nil and object:getIsAdditionalAttachment()) then
                    visit(object)
                    joints[#joints + 1] = { parent = v, child = object, joint = implement.jointDescIndex,
                        input = object:getActiveInputAttacherJointDescIndex() }
                end
            end
        end
    end
    visit(root)
    return vehicles, joints
end

function W.rootOf(v)
    return v.rootVehicle or v
end

-- Uloží polohu každého článku soupravy, jejich zapřažení a stav (složeno, světla, nářadí dole…), do kterého je reset vrátí.
function W.captureStart(rootVehicle)
    local vehicles, joints = collectCombination(rootVehicle)
    local start = { entries = {}, joints = {}, states = CinemaActions.readStates(vehicles, true) }
    for _, v in ipairs(vehicles) do
        local x, y, z = getWorldTranslation(v.rootNode)
        local rx, ry, rz = getWorldRotation(v.rootNode)
        start.entries[#start.entries + 1] = { uid = W.uid(v), x = x, y = y, z = z, rx = rx, ry = ry, rz = rz }
    end
    for _, j in ipairs(joints) do
        start.joints[#start.joints + 1] = { parent = W.uid(j.parent), child = W.uid(j.child), joint = j.joint, input = j.input }
    end
    return start
end

-- Přesune uložený start tak, aby první článek (tahač) stál v póze pose { x, y, z, rx, ry, rz }. Ostatní články zůstanou
-- vůči němu na svém místě: jejich posun od tahače se otočí o rozdíl směru (kolem svislé osy) a natočení se o něj změní.
-- Výměna vozidla herce takhle postaví jiné vozidlo (i s jeho vlekem) na místo původního startu.
function W.rebaseStart(start, pose)
    local root = start.entries[1]
    if root == nil then
        return
    end
    local ox, oy, oz, orx, ory, orz = root.x, root.y, root.z, root.rx, root.ry, root.rz
    local dyaw = pose.ry - ory
    local c, s = math.cos(dyaw), math.sin(dyaw)
    for k, e in ipairs(start.entries) do
        if k == 1 then
            e.x, e.y, e.z, e.rx, e.ry, e.rz = pose.x, pose.y, pose.z, pose.rx, pose.ry, pose.rz
        else
            local dx, dz = e.x - ox, e.z - oz
            e.x, e.y, e.z = pose.x + dx * c + dz * s, pose.y + (e.y - oy), pose.z - dx * s + dz * c
            e.rx, e.ry, e.rz = e.rx + (pose.rx - orx), e.ry + dyaw, e.rz + (pose.rz - orz)
        end
    end
end

-- Vrátí soupravu na uložený start, nebo na pózu, kterou pro každý článek vrátí placement(entry) → x, y, z, rx, ry, rz.
-- Vrací true, nebo false a důvod.
function W.resetStart(start, placement)
    if start == nil or start.entries == nil or #start.entries == 0 then
        return false, "noStart"
    end
    local resolved = {}
    for _, e in ipairs(start.entries) do
        local v = W.find(e.uid)
        if v == nil then
            return false, "missing"
        end
        resolved[#resolved + 1] = { vehicle = v, entry = e }
    end
    local mission = g_currentMission
    mission.isTeleporting = true
    local ok, err = pcall(function()
        -- odpojit vše, co je k soupravě teď zapřažené (i nářadí přidané po zapamatování startu)
        local _, current = collectCombination(resolved[1].vehicle)
        for i = #current, 1, -1 do
            local j = current[i]
            if j.child:getAttacherVehicle() ~= nil then
                j.child:getAttacherVehicle():detachImplementByObject(j.child, true)
            end
        end
        -- článek ze startu mezitím zapřažený k jinému vozidlu
        for _, r in ipairs(resolved) do
            local attacher = r.vehicle.getAttacherVehicle ~= nil and r.vehicle:getAttacherVehicle() or nil
            if attacher ~= nil then
                attacher:detachImplementByObject(r.vehicle, true)
            end
        end
        for _, r in ipairs(resolved) do
            r.vehicle:removeFromPhysics()
        end
        for _, r in ipairs(resolved) do
            local e = r.entry
            if placement ~= nil then
                r.vehicle:setAbsolutePosition(placement(e))
            else
                r.vehicle:setAbsolutePosition(e.x, e.y, e.z, e.rx, e.ry, e.rz)
            end
        end
        for _, r in ipairs(resolved) do
            r.vehicle:addToPhysics()
        end
        for _, j in ipairs(start.joints) do
            local parent, child = W.find(j.parent), W.find(j.child)
            if parent ~= nil and child ~= nil and parent.attachImplement ~= nil then
                parent:attachImplement(child, j.input, j.joint, true)
            end
        end
        resolved[1].vehicle.rotatedTime = 0
    end)
    mission.isTeleporting = false
    if not ok then
        Logging.warning("CinemaStudio: returning the vehicle to its start failed: %s", tostring(err))
        return false, "missing"
    end
    return true
end

---------------------------------------------------------------------------------------------------
-- zapřažení a odpojení

W.ATTACH_RANGE = 5 -- m; dál od sebe spoje nejdou spojit, jinak by fyzika soupravu vystřelila (skript vozidla nepřesouvá)

local function jointCompatible(tractor, joint, implement, input)
    if joint.jointType ~= input.jointType or (joint.jointIndex or 0) ~= 0 then
        return false
    end
    if AttacherJoints ~= nil and AttacherJoints.getAttacherJointCompatibility ~= nil then
        local ok, compatible = pcall(AttacherJoints.getAttacherJointCompatibility, tractor, joint, implement, input)
        if ok and compatible == false then
            return false
        end
    end
    return true
end

local function jointDistance(joint, input)
    if joint == nil or input == nil or joint.jointTransform == nil or input.node == nil then
        return math.huge
    end
    local ax, ay, az = getWorldTranslation(joint.jointTransform)
    local bx, by, bz = getWorldTranslation(input.node)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end

-- Dvojice spojů tahače a nářadí se stejným typem a volným spojem tahače, s nejmenší vzdáleností: spoj, vstup, vzdálenost;
-- nil, když žádná nesedí.
function W.findAttachJoints(tractor, implement)
    local joints = tractor.spec_attacherJoints ~= nil and tractor.spec_attacherJoints.attacherJoints or {}
    local inputs = implement.spec_attachable ~= nil and implement.spec_attachable.inputAttacherJoints or {}
    local best, bestInput, bestDistance = nil, nil, math.huge
    for j, joint in ipairs(joints) do
        for i, input in ipairs(inputs) do
            if jointCompatible(tractor, joint, implement, input) then
                local distance = jointDistance(joint, input)
                if distance < bestDistance then
                    best, bestInput, bestDistance = j, i, distance
                end
            end
        end
    end
    return best, bestInput, bestDistance
end

-- Zapřáhne nářadí k tahači (jako při návratu na start, bez událostí). Spoj a vstup lze zadat, jinak se hledají.
-- Vrací true, nebo false a důvod: self, attached, noJoint, tooFar, nebo text chyby.
function W.attach(tractor, implement, joint, input)
    if tractor == implement then
        return false, "self"
    end
    local current = implement.getAttacherVehicle ~= nil and implement:getAttacherVehicle() or nil
    if current == tractor then
        return true
    elseif current ~= nil then
        return false, "attached"
    end
    local distance
    if joint == nil or input == nil then
        joint, input, distance = W.findAttachJoints(tractor, implement)
        if joint == nil then
            return false, "noJoint"
        end
    else
        distance = jointDistance(tractor.spec_attacherJoints.attacherJoints[joint], implement.spec_attachable.inputAttacherJoints[input])
    end
    if distance > W.ATTACH_RANGE then
        return false, "tooFar"
    end
    local ok, err = pcall(tractor.attachImplement, tractor, implement, input, joint, true)
    if not ok then
        return false, tostring(err)
    end
    return true
end

-- Odpojí nářadí od tahače, bez nářadí všechno, co tahač nese. Vrací počet odpojených.
function W.detach(tractor, implement)
    local list = {}
    for _, attached in ipairs(tractor:getAttachedImplements()) do
        if implement == nil or attached.object == implement then
            list[#list + 1] = attached.object
        end
    end
    for _, object in ipairs(list) do
        tractor:detachImplementByObject(object, true)
    end
    return #list
end

---------------------------------------------------------------------------------------------------
-- herci: jízda po trase

function W.canDrive(v)
    if v == nil or v.spec_drivable == nil or v.getIsMotorStarted == nil then
        return false, "notDrivable"
    end
    if g_currentMission ~= nil and not g_currentMission:getIsServer() then
        return false, "notServer"
    end
    local player = g_localPlayer
    if player ~= nil and player.getCurrentVehicle ~= nil then
        local current = player:getCurrentVehicle()
        if current ~= nil and W.rootOf(current) == v then
            return false, "occupied"
        end
    end
    if v.getIsAIActive ~= nil and v:getIsAIActive() then
        return false, "aiActive"
    end
    return true
end

W.CATCH_UP_GAIN = 1.8 -- km/h navíc za každý metr za plánovanou polohou (jízda podle křivky)
W.CATCH_UP_MAX = 25 -- km/h; nejvíc navíc
W.CATCH_UP_STOP = 1 -- m; v stání podle křivky auto dojede na plánované místo, když chybí víc

-- Běhový stav herce (neukládá se): rt = { route, s, state = "waiting" | "driving" | "done", vehicle } a stav
-- tempomatu a motoru před jízdou, který se po jízdě vrátí.
function W.newRuntime(actor)
    local plan = R.plan(actor)
    local route = plan ~= nil and plan.route or nil
    local start = actor.start ~= nil and actor.start.entries ~= nil and actor.start.entries[1] or nil
    local vehicle = start ~= nil and W.find(start.uid) or nil
    local rt = { route = route, s = 0, state = "waiting", vehicle = vehicle, name = actor.name,
        pauses = plan ~= nil and (plan.curve ~= nil and plan.holds or plan.pauses) or {}, pauseIndex = 1,
        curve = plan ~= nil and plan.curve or nil, plan = plan }
    if usable(vehicle) then
        local cc = vehicle.spec_drivable ~= nil and vehicle.spec_drivable.cruiseControl or nil
        if cc ~= nil then
            rt.cruiseSpeed, rt.cruiseReverse = cc.speed, cc.speedReverse
        end
        rt.motorWasOn = vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted()
    end
    return rt
end

---------------------------------------------------------------------------------------------------
W.DROP_HEIGHT = 1 -- m nad terénem, odkud se souprava přenese a nechá spadnout

-- Přenese soupravu (vozidlo i zapřažené nářadí) tak, aby kořen stál na (x, z) W.DROP_HEIGHT nad terénem; natočení
-- a vzájemná poloha článků zůstanou. Fyzika ji nechá dopadnout. Vrací true, nebo false a důvod.
function W.dropAt(root, x, z)
    local start = W.captureStart(root)
    local r = start.entries[1]
    if r == nil then
        return false, "missing"
    end
    local ty = W.terrainY(x, z) + W.DROP_HEIGHT
    return W.resetStart(start, function(e)
        return x + (e.x - r.x), ty + (e.y - r.y), z + (e.z - r.z), e.rx, e.ry, e.rz
    end)
end

-- řidič ve vozidle: postava pomocníka jako u AI (vanilla Enterable:setVehicleCharacter)

-- Pomocníci z herního HelperManageru: { name, title, playerStyle }.
function W.helperList()
    local list = {}
    if g_helperManager ~= nil then
        for i = 1, g_helperManager.numHelpers do
            list[#list + 1] = g_helperManager.indexToHelper[i]
        end
    end
    return list
end

function W.hasDriverSeat(v)
    return v ~= nil and v.setVehicleCharacter ~= nil and v.restoreVehicleCharacter ~= nil
        and v.spec_enterable ~= nil and v.spec_enterable.vehicleCharacter ~= nil
end

-- Posadí do vozidla pomocníka podle jména (s vlastním vzhledem style, je-li), bez jména řidiče odebere. false, když
-- to vozidlo neumí nebo v něm sedí hráč.
function W.setDriver(v, name, style)
    if not W.hasDriverSeat(v) or (v.getIsControlled ~= nil and v:getIsControlled()) then
        return false
    end
    local ok = pcall(function()
        if name == nil then
            v:restoreVehicleCharacter()
        else
            style = style or CinemaPerson.styleOf(name)
            if style == nil then
                error("unknown helper " .. tostring(name))
            end
            v:setVehicleCharacter(style)
        end
    end)
    return ok
end

---------------------------------------------------------------------------------------------------
-- hodnoty s rozsahem, které jde řídit křivkou v čase: nejvyšší rychlost stroje a osy pohyblivých částí (vanilla Cylindered)

W.DEFAULT_MAX_KMH = 80

-- Nejvyšší rychlost vozidla (km/h) podle tempomatu; bez ní výchozí hodnota.
function W.maxSpeedKmh(v)
    local cc = v ~= nil and v.spec_drivable ~= nil and v.spec_drivable.cruiseControl or nil
    if cc ~= nil and cc.maxSpeed ~= nil and cc.maxSpeed > 1 then
        return cc.maxSpeed
    end
    return W.DEFAULT_MAX_KMH
end

-- Osy vozidla (ramena, výsuvy, náklony…), které mají rozsah: { index, label, unit, min, max, get(v), set(v, value) }.
-- Rotace v stupních, posuv v metrech, animace v procentech. Hodnoty se čtou a zapisují přes vanilla Cylindered.
function W.toolAxes(v)
    local out = {}
    local spec = v ~= nil and v.spec_cylindered or nil
    if spec == nil or spec.movingTools == nil then
        return out
    end
    for index, tool in ipairs(spec.movingTools) do
        if tool.node ~= nil and tool.hasRequiredConfigurations ~= false then
            local label = nil
            if tool.axis ~= nil and g_i18n ~= nil and g_i18n:hasText("input_" .. tool.axis) then
                label = g_i18n:getText("input_" .. tool.axis)
            end
            label = label or getName(tool.node)
            local def = { index = index, label = label }
            if tool.rotMin ~= nil and tool.rotMax ~= nil and tool.rotationAxis ~= nil then
                def.unit, def.min, def.max = "°", math.deg(tool.rotMin), math.deg(tool.rotMax)
                def.get = function()
                    local r = { getRotation(tool.node) }
                    return math.deg(r[tool.rotationAxis])
                end
                def.set = function(vehicle, value)
                    Cylindered.setAbsoluteToolRotation(vehicle, tool, math.rad(value))
                end
            elseif tool.transMin ~= nil and tool.transMax ~= nil and tool.translationAxis ~= nil then
                def.unit, def.min, def.max = "m", tool.transMin, tool.transMax
                def.get = function()
                    local p = { getTranslation(tool.node) }
                    return p[tool.translationAxis]
                end
                def.set = function(vehicle, value)
                    Cylindered.setAbsoluteToolTranslation(vehicle, tool, value)
                end
            elseif tool.animName ~= nil and v.getAnimationTime ~= nil then
                def.unit, def.min, def.max = "%", (tool.animMinTime or 0) * 100, (tool.animMaxTime or 1) * 100
                def.get = function(vehicle)
                    return vehicle:getAnimationTime(tool.animName) * 100
                end
                def.set = function(vehicle, value)
                    vehicle:setAnimationTime(tool.animName, value / 100, nil, true)
                end
            else
                def = nil
            end
            if def ~= nil and def.max > def.min then
                out[#out + 1] = def
            end
        end
    end
    return out
end

local function brake(v, dt)
    pcall(AIVehicleUtil.driveToPoint, v, dt, 0, false, true, 0, 1, 0, true)
end

-- Motorized:onUpdateTick zhasne motor vozidla bez řidiče (automatický start po 250 ms, ruční start daleko
-- od hráče); během jízdy se oba časovače drží na začátku.
function W.keepMotorAlive(v)
    local spec = v.spec_motorized
    if spec ~= nil then
        spec.motorNotRequiredTimer = 0
        if spec.motorStopTimerDuration ~= nil then
            spec.motorStopTimer = spec.motorStopTimerDuration
        end
    end
end

-- Souprava, která umí couvat po trase: vozidlo bez tažného přívěsu a nářadí na kolech (to by se při couvání složilo).
function W.canReverse(v)
    local function towed(x)
        if x.getAttachedImplements == nil then
            return false
        end
        for _, implement in ipairs(x:getAttachedImplements()) do
            local object = implement.object
            if object ~= nil then
                local wheels = object.spec_wheels
                if (wheels ~= nil and #(wheels.wheels or {}) > 0) or towed(object) then
                    return true
                end
            end
        end
        return false
    end
    return v == nil or not towed(v)
end

-- Úsek mezi dvěma body změny směru, na kterém vozidlo teď jede: od kam (floorS), kam (ceilS) a jestli couvá.
local function legOf(rt)
    local floorS, ceilS = 0, rt.route.length
    for k, p in ipairs(rt.pauses) do
        if p.cusp then
            if k < rt.pauseIndex then
                floorS = p.s
            else
                ceilS = p.s
                break
            end
        end
    end
    return floorS, ceilS, R.reverseAt(rt.route, floorS + 1e-3)
end

-- Uzel, vůči kterému se počítá cíl řízení: při couvání uzel pro couvání kloubových a otočených vozidel (jako Courseplay).
local function steeringNode(v, reverse)
    if reverse then
        local articulated = v.spec_articulatedAxis
        local node = v.getAIReverserNode ~= nil and v:getAIReverserNode() or nil
        if node == nil and articulated ~= nil then
            node = articulated.aiRevereserNode
        end
        if node ~= nil then
            return node
        end
    end
    return v.getAIDirectionNode ~= nil and v:getAIDirectionNode() or v.rootNode
end

function W.driveActor(rt, actor, dt)
    local v = rt.vehicle
    if rt.route == nil or not usable(v) then
        rt.state = "done"
        return
    end
    -- bez řidiče je vozidlo „neaktivní“ a jeho kola se nenatáčejí (Wheels aktualizuje natočení jen u aktivního vozidla)
    -- původní stav si drží vozidlo, ne rt: rt se při úpravách zahazuje a další jízda by si za původní vzala náš přepis
    if v.cinemaDriven == nil then
        -- s hráčem uvnitř by Drivable každý snímek řídil podle jeho (prázdného) vstupu a přebíjel naše řízení; AI to
        -- obchází stejně, přes getIsVehicleControlledByPlayer
        v.cinemaDriven = { force = v.forceIsActive, control = rawget(v, "getIsVehicleControlledByPlayer") }
        v.getIsVehicleControlledByPlayer = function() return false end
    end
    v.forceIsActive = true
    local x, _, z = getWorldTranslation(v.rootNode)
    if rt.located then
        local floorS, ceilS = legOf(rt)
        rt.s = R.project(rt.route, x, z, rt.s, nil, floorS, ceilS)
    else
        rt.s, rt.located = R.project(rt.route, x, z), true
    end
    -- pauzy, které vozidlo už minulo (přehrávání od playheadu uprostřed trasy), se přeskočí
    while rt.pauses[rt.pauseIndex] ~= nil and rt.s > rt.pauses[rt.pauseIndex].s + R.ARRIVE do
        rt.pauseIndex = rt.pauseIndex + 1
    end
    local _, ceilS, reverse = legOf(rt)
    if rt.holdLeft ~= nil then
        rt.holdLeft = rt.holdLeft - dt * 0.001
        brake(v, dt)
        W.keepMotorAlive(v)
        v:raiseActive()
        if rt.holdLeft <= 0 then
            rt.holdLeft = nil
            rt.pauseIndex = rt.pauseIndex + 1
        end
        return
    end
    local pause = rt.pauses[rt.pauseIndex]
    local cruise = math.max(R.cruiseAt(rt.route, rt.s), 1)
    local kmh = R.targetSpeed(rt.route, rt.s, cruise, pause ~= nil and pause.s or nil)
    local curveActive = false
    if rt.curve ~= nil then
        curveActive = CinemaChannels.isActive(rt.curve, rt.elapsed or 0) or R.curveStopped(rt.curve, rt.elapsed or 0)
        rt.curveWant = curveActive and math.max(CinemaChannels.valueAt(rt.curve, rt.elapsed or 0) or 0, 0) or nil
        rt.elapsed = (rt.elapsed or 0) + dt * 0.001
    end
    if curveActive then
        -- rychlost podle křivky v čase od startu jízdy (jen mezi jejím prvním a posledním bodem, za koncem s nulou dál
        -- stojí; jinak podle bodů trasy); nulová rychlost = vozidlo drží (brzdí) a čeká
        local want = rt.curveWant
        -- křivka dává rychlost podle času; skutečné auto se rozjíždí a zatáčí po svém, takže se drží plánované polohy:
        -- za plánem přidá, před ním ubere (jinak by zpoždění z rozjezdu už nedohnalo a osa by ukazovala jinde)
        if rt.plan ~= nil and rt.plan.sampled ~= nil then
            local _, _, planned = R.positionAtTime(rt.plan, rt.elapsed - dt * 0.001)
            local lag = planned - rt.s
            if want < 0.5 then
                want = lag > W.CATCH_UP_STOP and math.min(lag * W.CATCH_UP_GAIN, W.CATCH_UP_MAX) or 0
            else
                want = math.max(want + M.clamp(lag * W.CATCH_UP_GAIN, -want * 0.5, W.CATCH_UP_MAX), 0)
            end
        end
        if reverse then
            want = math.min(want, R.REVERSE_KMH)
        end
        if rt.route.length - rt.s <= R.ARRIVE then
            W.parkActor(rt, dt)
            return
        end
        if pause ~= nil then
            local remaining = pause.s - rt.s
            if remaining <= R.ARRIVE then
                rt.holdLeft = pause.dur
                brake(v, dt)
                W.keepMotorAlive(v)
                v:raiseActive()
                return
            end
            want = math.min(want, math.sqrt(2 * R.DECEL * (remaining - R.ARRIVE)) * 3.6)
        end
        if want < 0.5 then
            brake(v, dt)
            W.keepMotorAlive(v)
            v:raiseActive()
            return
        end
        kmh, cruise = want, math.max(want, 1)
    end
    if kmh <= 0 then
        if pause ~= nil then
            rt.holdLeft = pause.dur
            if CinemaDev ~= nil then CinemaDev.drive("pause", rt, v, pause) end
            brake(v, dt)
            return
        end
        W.parkActor(rt, dt)
        return
    end
    if not rt.started and CinemaDev ~= nil then CinemaDev.drive("start", rt, v) end
    rt.started = true
    local look = R.lookahead(cruise)
    look = R.lookahead(cruise, R.turnAhead(rt.route, rt.s, look))
    local tx, tz = R.pointAt(rt.route, math.min(rt.s + look, ceilS))
    local lx, _, lz = worldToLocal(steeringNode(v, reverse), tx, W.terrainY(tx, tz), tz)
    W.keepMotorAlive(v)
    if not v:getIsMotorStarted() then
        v:startMotor()
    end
    if v.setCruiseControlMaxSpeed ~= nil and (rt.cruiseSet == nil or math.abs(rt.cruiseSet - cruise) > 0.5) then
        v:setCruiseControlMaxSpeed(cruise, cruise)
        rt.cruiseSet = cruise
    end
    AIVehicleUtil.driveToPoint(v, dt, 1, true, not reverse, lx, lz, kmh, false)
    v:raiseActive()
    if CinemaDev ~= nil then CinemaDev.drive("step", rt, v, { dt = dt, x = x, z = z, lx = lx, lz = lz, kmh = kmh }) end
end

-- Konec trasy za přehrávání: vozidlo zastaví a stojí s běžícím motorem (vypne ho až stopActor po přehrávání), takže
-- na něm můžou dál běžet akce na ose.
local function release(rt, v)
    if usable(v) and v.cinemaDriven ~= nil then
        v.forceIsActive = v.cinemaDriven.force == true
        v.getIsVehicleControlledByPlayer = v.cinemaDriven.control
        v.cinemaDriven = nil
    end
end

function W.parkActor(rt, dt)
    local v = rt.vehicle
    release(rt, v)
    if usable(v) and rt.started then
        brake(v, dt or 16)
        if v.setCruiseControlState ~= nil and Drivable ~= nil then
            v:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF, true)
        end
    end
    rt.state, rt.parked = "done", true
end

-- Zastaví a vrátí tempomat i motor do stavu před jízdou (jinak by se vozidlo po nasednutí samo rozjelo).
function W.stopActor(rt, dt)
    local v = rt.vehicle
    release(rt, v)
    if usable(v) and rt.started then
        brake(v, dt or 16)
        if v.setCruiseControlState ~= nil and Drivable ~= nil then
            v:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF, true)
        end
        if rt.cruiseSpeed ~= nil and v.setCruiseControlMaxSpeed ~= nil then
            v:setCruiseControlMaxSpeed(rt.cruiseSpeed, rt.cruiseReverse or rt.cruiseSpeed)
        end
        if not rt.motorWasOn and v.stopMotor ~= nil then
            v:stopMotor()
        end
        rt.started = false
    end
    rt.state, rt.parked = "done", false
end
