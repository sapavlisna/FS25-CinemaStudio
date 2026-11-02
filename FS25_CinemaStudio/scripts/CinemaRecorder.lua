-- Nahrávání ruční jízdy a chůze: klávesou se záznam zapne a vypne. Běží přes nástup i výstup: pěšky se nahrává chůze (skoky,
-- zvednuté předměty a jak je natáčí), ve vozidle jeho jízda, a když hráč nastoupí nebo vystoupí, začne další díl záznamu.
-- Hotová nahrávka (CinemaRecording) čeká, až se otevře editor, a vloží se do záběru jako vozidlo, postava, nebo postava
-- s akcemi Nastoupit a Vystoupit a vozidly, pokud se v záznamu střídala chůze s jízdou.

CinemaRecorder = CinemaRecorder or {}
local Rec = CinemaRecorder
local W = CinemaWorld
local Pe = CinemaPerson

Rec.state = nil
Rec.pending = nil

local function notify(key, ...)
    local text = string.format(g_i18n:getText(key), ...)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, text)
    end
end

local function playerRoot()
    local player = g_localPlayer
    local v = player ~= nil and player.getCurrentVehicle ~= nil and player:getCurrentVehicle() or nil
    return v ~= nil and W.rootOf(v) or nil
end

function Rec.isActive()
    return Rec.state ~= nil
end

-- Uzel, který hráč drží v rukou (HandToolHands), nebo nil.
local function heldNode(player)
    local spec = player.hands ~= nil and player.hands.spec_hands or nil
    local node = spec ~= nil and spec.heldItemNode or nil
    if node == nil or node == 0 or not entityExists(node) then
        return nil
    end
    return node
end

local function isJumping(player)
    local sm = player.stateMachine
    local foot = sm ~= nil and sm.states ~= nil and sm.states.onFoot or nil
    if foot ~= nil and foot.states ~= nil and foot.states.jumping ~= nil then
        return foot.currentState == foot.states.jumping
    end
    local ic = player.inputComponent
    return ic ~= nil and (ic.lastJumpPower or 0) > 0
end

-- Cíl nesení pro uzel v rukou a uzel, jehož polohu akce nesení nastavuje: malé vozidlo (paleta, kanystr), jinak předmět
-- mapy; nil, když je předmět na nesení moc velký.
local function carryTarget(node)
    local object = g_currentMission.getNodeObject ~= nil and g_currentMission:getNodeObject(node) or nil
    local ok, isVehicle = pcall(function() return object ~= nil and Vehicle ~= nil and object:isa(Vehicle) end)
    if ok and isVehicle and object.rootNode ~= nil then
        return CinemaPerson.carryFromVehicle(object), object.rootNode
    end
    local target = CinemaPerson.carryFromShape(node)
    return target, target ~= nil and CinemaPerson.carryNodes[target] or nil
end

local function newWalkPart()
    return { kind = "walk", rec = CinemaRecording.newPerson(), name = g_i18n:getText("cine_rec_walkName") }
end

local function newDrivePart(root)
    local start = W.captureStart(root)
    local vehicles, axes, defs = {}, {}, {}
    for e, entry in ipairs(start.entries) do
        local v = W.find(entry.uid)
        vehicles[e] = v
        for _, def in ipairs(v ~= nil and W.toolAxes(v) or {}) do
            local id = string.format("tool:%d:%d", e, def.index)
            axes[#axes + 1] = { id = id, min = def.min, max = def.max }
            defs[#defs + 1] = { id = id, vehicle = v, get = def.get }
        end
    end
    return { kind = "drive", root = root, start = start, vehicles = vehicles, defs = defs, rec = CinemaRecording.new(axes),
        name = W.name(root), uid = start.entries[1].uid }
end

local function openPart(root)
    if root == nil then
        notify("cine_rec_startedWalk")
        return newWalkPart()
    end
    local part = newDrivePart(root)
    notify("cine_rec_started", part.name)
    return part
end

function Rec.start()
    local player = g_localPlayer
    local root = nil
    if player == nil or Pe.playerVehicle() ~= nil then
        root = playerRoot()
        if root == nil or root.spec_drivable == nil then
            notify("cine_rec_noVehicle")
            return
        end
    end
    local st = { parts = {}, part = openPart(root), time = 0, nextSample = 0 }
    if root ~= nil then
        -- záznam začíná ve vozidle: postava (když přijde chůze po výstupu) začíná u jeho dveří
        local ok, x, z, yaw = pcall(Pe.exitPose, root)
        if ok and x ~= nil then
            st.driverStart = { x = x, y = W.terrainY(x, z), z = z, yaw = yaw }
        end
    end
    Rec.state = st
end

local function heldPose(part)
    local node = part.carry ~= nil and part.carry.node or nil
    if node == nil or not entityExists(node) then
        return nil
    end
    local x, y, z = getWorldTranslation(node)
    local rx, ry, rz = getWorldRotation(node)
    return { x = x, y = y, z = z, rx = rx, ry = ry, rz = rz }
end

local function takeStep(st, part)
    local x, y, z = Pe.playerPos()
    CinemaRecording.addStep(part.rec, st.time, x, y, z, W.terrainY(x, z), Pe.playerYaw(), heldPose(part))
end

-- Každý snímek chůze: skok (náběžná hrana) a zvednutí nebo položení předmětu.
local function watchWalk(st, part)
    local player = g_localPlayer
    local jumping = isJumping(player)
    if jumping and not part.jumping then
        CinemaRecording.jump(part.rec, st.time)
    end
    part.jumping = jumping
    local node = heldNode(player)
    if node ~= (part.carry ~= nil and part.carry.held or nil) then
        if part.carry ~= nil then
            CinemaRecording.drop(part.rec, st.time)
            part.carry = nil
        end
        if node ~= nil then
            local target, poseNode = carryTarget(node)
            part.carry = { held = node, node = target ~= nil and poseNode or nil }
            if target ~= nil then
                CinemaRecording.pickUp(part.rec, st.time, target, Pe.playerYaw())
            end
        end
    end
end

local function take(st)
    local part = st.part
    if part.kind == "walk" then
        takeStep(st, part)
        return
    end
    if part.root.isDeleted then
        return
    end
    local x, _, z = getWorldTranslation(part.root.rootNode)
    local axisValues = {}
    for _, d in ipairs(part.defs) do
        local ok, value = pcall(d.get, d.vehicle)
        if ok then
            axisValues[d.id] = value
        end
    end
    CinemaRecording.add(part.rec, st.time, x, z, part.root:getLastSpeed(), part.root.movingDirection, axisValues,
        CinemaActions.readStates(part.vehicles))
end

local function personOptions()
    return { gaits = { slow = Pe.SLOW_KMH, walk = Pe.WALK_KMH, run = Pe.RUN_KMH }, hold = Pe.holdOffset,
        carryCurves = Pe.CARRY_CURVES, carryTurns = Pe.CARRY_TURNS }
end

-- Z dílů záznamu nahrávka: jeden díl dá jízdu nebo chůzi jako dřív, víc dílů (chůze a jízda) postavu s nástupy a výstupy.
local function buildResult(st)
    local parts = st.parts
    if #parts == 1 then
        local part = parts[1]
        if part.kind == "walk" then
            local result = CinemaRecording.finishPerson(part.rec, personOptions())
            if result == nil then
                return nil, "cine_rec_tooShortWalk"
            end
            result.name = part.name
            return result
        end
        local result = CinemaRecording.finish(part.rec)
        if result == nil then
            return nil, "cine_rec_tooShort"
        end
        result.name, result.start = part.name, part.start
        return result
    end
    local result = CinemaRecording.assemble(parts, { person = personOptions(), driverStart = st.driverStart })
    if result == nil then
        return nil, "cine_rec_tooShortWalk"
    end
    result.name = g_i18n:getText("cine_rec_sessionName")
    return result
end

function Rec.stop()
    local st = Rec.state
    if st == nil then
        return
    end
    Rec.state = nil
    if st.part.kind ~= "walk" or Pe.playerVehicle() == nil then
        take(st)
    end
    st.parts[#st.parts + 1] = st.part
    local result, problem = buildResult(st)
    if result == nil then
        notify(problem)
        return
    end
    Rec.pending = result
    notify("cine_rec_done", result.name, result.duration)
end

function Rec.toggle()
    if Rec.state ~= nil then
        Rec.stop()
    else
        Rec.start()
    end
end

-- Hráč nastoupil nebo vystoupil (nebo přesedl): hotový díl se uloží a začne další podle toho, kde hráč teď je.
local function switchPart(st, root)
    if st.part.kind == "drive" then
        take(st)
    end
    st.parts[#st.parts + 1] = st.part
    st.part = openPart(root)
    take(st)
    st.nextSample = st.time + CinemaRecording.SAMPLE_DT
end

function Rec.update(dt)
    local st = Rec.state
    if st == nil then
        return
    end
    local part = st.part
    if g_localPlayer == nil or (part.kind == "drive" and part.root.isDeleted) then
        Rec.stop()
        return
    end
    local root = playerRoot()
    if root ~= nil and root.spec_drivable == nil then
        Rec.stop()
        return
    end
    if root ~= (part.kind == "drive" and part.root or nil) then
        switchPart(st, root)
        part = st.part
    end
    st.time = st.time + dt * 0.001
    if part.kind == "walk" then
        watchWalk(st, part)
    end
    if st.time >= st.nextSample then
        take(st)
        st.nextSample = st.time + CinemaRecording.SAMPLE_DT
    end
end

function Rec.draw()
    local st = Rec.state
    if st == nil or (g_gui ~= nil and g_gui:getIsGuiVisible()) then
        return
    end
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 0.25, 0.2, 1)
    renderText(0.5, 0.94, 0.02, string.format(g_i18n:getText("cine_rec_status"), math.floor(st.time / 60), math.floor(st.time % 60)))
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
end
