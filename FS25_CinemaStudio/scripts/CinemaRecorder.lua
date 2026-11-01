-- Nahrávání ruční jízdy: klávesou se zapne a vypne záznam vozidla, ve kterém hráč sedí. Hotová nahrávka (CinemaRecording)
-- čeká, až se otevře editor, a vloží se do záběru jako nové vozidlo s trasou, křivkami a akcemi.

CinemaRecorder = CinemaRecorder or {}
local Rec = CinemaRecorder
local W = CinemaWorld

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

function Rec.start()
    local root = playerRoot()
    if root == nil or root.spec_drivable == nil then
        notify("cine_rec_noVehicle")
        return
    end
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
    Rec.state = { root = root, start = start, vehicles = vehicles, defs = defs, rec = CinemaRecording.new(axes), time = 0,
        nextSample = 0, name = W.name(root) }
    notify("cine_rec_started", Rec.state.name)
end

local function take(st)
    local x, _, z = getWorldTranslation(st.root.rootNode)
    local axisValues = {}
    for _, d in ipairs(st.defs) do
        local ok, value = pcall(d.get, d.vehicle)
        if ok then
            axisValues[d.id] = value
        end
    end
    CinemaRecording.add(st.rec, st.time, x, z, st.root:getLastSpeed(), st.root.movingDirection, axisValues,
        CinemaActions.readStates(st.vehicles))
end

function Rec.stop()
    local st = Rec.state
    if st == nil then
        return
    end
    Rec.state = nil
    take(st)
    local result = CinemaRecording.finish(st.rec)
    if result == nil then
        notify("cine_rec_tooShort")
        return
    end
    result.name, result.start = st.name, st.start
    Rec.pending = result
    notify("cine_rec_done", st.name, result.duration)
end

function Rec.toggle()
    if Rec.state ~= nil then
        Rec.stop()
    else
        Rec.start()
    end
end

function Rec.update(dt)
    local st = Rec.state
    if st == nil then
        return
    end
    if st.root.isDeleted or playerRoot() ~= st.root then
        Rec.stop()
        return
    end
    st.time = st.time + dt * 0.001
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
