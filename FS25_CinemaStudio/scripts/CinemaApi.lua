-- Veřejné API pro jiné mody (DashControl, MCP): globál _G.CinemaStudioApi (též CinemaStudio.api). Všechny funkce vrací
-- ok, výsledek | chybovou zprávu a nikdy nehodí chybu. Záběry se číslují od 1 podle pořadí v seznamu savegame; funkce, které
-- potřebují editor (openShot, play, reset, setCameraPose), ho samy otevřou; listShots, getShotXml, putShotXml, poseAt, pinActor,
-- místa a status jdou i se zavřeným editorem a s otevřeným pracují s jeho rozpracovaným záběrem.
--
--   version                          1
--   listShots()                      → { { index, name, duration, file, active } }
--   getShotXml(n)                    → text XML záběru
--   putShotXml(n | nil, xmlText, force?) → n, { warnings }; nil = nový záběr. Text se zapíše do dočasného souboru, načte přes
--                                    CinemaStorage a bez chyb uloží (neplatný se neuloží, vrátí důvod; force uloží i s chybami),
--                                    krok jde do historie. warnings = vozidla v záběru, která ve hře nejsou.
--   openShot(n), closeEditor()
--   play(n)                          od začátku (jako R a mezerník), status() → { playing, shot, t, duration, editorOpen, prerollLeft }
--   stop(), reset(n)                 reset = R
--   poseAt(n, t)                     → { x, y, z, qx, qy, qz, qw, focal }; bez otevřeného editoru
--   setCameraPose(pose)              volná kamera editoru bez jeho ovládacích prvků (pro snímky)
--   pinActor(n, uniqueId)            → id herce; start a stavy (špína, opotřebení, nádrže, bedna) podle vozidla ve hře
--   getPlaces(), setPlace(name, { x, y, z, yaw, note }), deletePlace(name)   places.xml savegame
--   reload()                         jen ve vývoji (scripts/dev/CinemaDev.lua): skripty a překlady znovu z dev_source.xml
--                                    → { files, texts, dir }; ve vydaném módu chybí

CinemaApi = CinemaApi or {}
local Api = CinemaApi
local S = CinemaShot
local St = CinemaStorage
local W = CinemaWorld
local M = CinemaMath

Api.version = 1
Api.TEMP_FILE = "_put"
Api.NAME_MAX = 80

local function guard(fn)
    return function(...)
        local ok, result, extra = pcall(fn, ...)
        if not ok then
            return false, tostring(result)
        end
        return true, result, extra
    end
end

local function inGame()
    if g_currentMission == nil then
        error("no game is loaded", 0)
    end
end

local function screen()
    local scr = CinemaEditorScreen ~= nil and CinemaEditorScreen.INSTANCE or nil
    if scr ~= nil and scr.mission ~= g_currentMission then
        return nil
    end
    return scr
end

local function isOpen(scr)
    return scr ~= nil and scr:getIsOpen() == true
end

-- Seznam záběrů: živý z editoru, když ho má načtený, jinak z disku.
local function liveIndex()
    local scr = screen()
    if scr ~= nil and scr.index ~= nil then
        return scr.index
    end
    return St.loadIndex()
end

local function fileOf(n)
    local index = liveIndex()
    local i = type(n) == "number" and math.floor(n) or nil
    local file = i ~= nil and index.files[i] or nil
    if file == nil then
        error(string.format("shot %s does not exist (there are %d)", tostring(n), #index.files), 0)
    end
    return file, i, index
end

local function shotName(i)
    return string.format(g_i18n:getText("cine_shotName"), i)
end

-- Záběr n: rozpracovaný v otevřeném editoru, jinak z disku (nový, ještě neuložený je prázdný).
local function shotFor(n)
    local file, i = fileOf(n)
    local scr = screen()
    if isOpen(scr) and scr.shot ~= nil and scr.index ~= nil and scr.index.active == i then
        return scr.shot, i
    end
    local shot = St.load(file)
    if shot == nil then
        shot = S.new(file)
        shot.file = file
    end
    if shot.name == nil or shot.name == "" or shot.name == file then
        shot.name = shotName(i)
    end
    return shot, i
end

-- Uloží rozpracované změny editoru, aby disk odpovídal tomu, co je vidět.
local function flush()
    local scr = screen()
    if scr ~= nil and scr.shot ~= nil then
        scr:saveAll()
    end
end

local function ensureEditor()
    inGame()
    if not isOpen(screen()) then
        CinemaStudio.onOpenEditor(CinemaStudio)
    end
    local scr = screen()
    if not isOpen(scr) then
        error("the editor could not be opened", 0)
    end
    return scr
end

local function writeText(path, text)
    local f = io.open(path, "w")
    if f == nil then
        return false
    end
    f:write(text)
    f:close()
    return true
end

local function readText(path)
    local id = loadXMLFile("cinemaShotRaw", path)
    if id == nil or id == 0 then
        return nil
    end
    local text = saveXMLFileToMemory(id)
    delete(id)
    return text
end

local function appendHistory(file, before, after)
    local entries = St.loadHistory(file)
    entries[#entries + 1] = { time = CinemaHistory.now(), snap = S.clone(before) }
    entries = CinemaHistory.prune(entries, CinemaHistory.now())
    CinemaHistory.compact(entries, S.clone(after))
    St.saveHistory(file, entries)
end

-- Co v záběru míří na vozidlo, které ve hře není: texty upozornění.
function Api.missingVehicles(shot, find)
    local warnings, seen = {}, {}
    local function check(uid, where)
        if uid ~= nil and not seen[uid .. where] and find(uid) == nil and S.personOfTarget(shot, uid) == nil and S.pointOfTarget(shot, uid) == nil then
            seen[uid .. where] = true
            warnings[#warnings + 1] = string.format("vehicle %s (%s) is not in the game", tostring(uid), where)
        end
    end
    for _, a in ipairs(shot.actors) do
        if not a.person then
            for _, e in ipairs(a.start ~= nil and a.start.entries or {}) do
                check(e.uid, "herec " .. tostring(a.name))
            end
        end
        for _, action in ipairs(a.actions or {}) do
            check(action.vehicle, "akce " .. tostring(action.kind) .. " herce " .. tostring(a.name))
        end
    end
    for _, cam in ipairs(shot.cameras) do
        for _, seg in ipairs(cam.segments or {}) do
            check(seg.track.target, "camera block target")
        end
        for _, f in ipairs(cam.focus or {}) do
            check(f.target, "point of interest")
        end
    end
    return warnings
end

-- Póza kamery z tabulky { x, y, z, qx, qy, qz, qw, focal }: čísla a normalizovaný kvaternion; nil a důvod při vadě.
function Api.normalizePose(pose)
    if type(pose) ~= "table" then
        return nil, "pose is not a table"
    end
    for _, key in ipairs({ "x", "y", "z", "qx", "qy", "qz", "qw" }) do
        local v = pose[key]
        if type(v) ~= "number" or v ~= v or math.abs(v) == math.huge then
            return nil, "pose: missing number " .. key
        end
    end
    local q = M.quatNormalize({ pose.qx, pose.qy, pose.qz, pose.qw })
    return { x = pose.x, y = pose.y, z = pose.z, q = q, focal = M.clampFocal(tonumber(pose.focal) or 35) }
end

-- Místo z jména a tabulky { x, y, z?, yaw?, note? }; chybějící y se dopočítá z terénu.
function Api.makePlace(name, p, terrainY)
    if type(name) ~= "string" or name:match("^%s*$") then
        return nil, "place has no name"
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if #name > Api.NAME_MAX then
        return nil, string.format("place name is longer than %d characters", Api.NAME_MAX)
    end
    if type(p) ~= "table" or type(p.x) ~= "number" or type(p.z) ~= "number" then
        return nil, "place: missing x or z"
    end
    local y = tonumber(p.y)
    if y == nil and terrainY ~= nil then
        y = terrainY(p.x, p.z)
    end
    if y == nil then
        return nil, "place: missing y"
    end
    local note = type(p.note) == "string" and p.note ~= "" and p.note or nil
    return { name = name, x = p.x, y = y, z = p.z, yaw = tonumber(p.yaw) or 0, note = note }
end

---------------------------------------------------------------------------------------------------
-- záběry

if CinemaDev ~= nil then Api.reload = guard(function() return CinemaDev.reload() end) end

Api.listShots = guard(function()
    inGame()
    local index = liveIndex()
    local list = {}
    for i, file in ipairs(index.files) do
        local shot = shotFor(i)
        list[i] = { index = i, name = shot.name or shotName(i), duration = S.duration(shot), file = file, active = index.active == i }
    end
    return list
end)

Api.getShotXml = guard(function(n)
    inGame()
    local file, i = fileOf(n)
    flush()
    local path = St.getPath(file)
    if not fileExists(path) then
        local shot = shotFor(i)
        shot.file = file
        St.save(shot)
    end
    local text = readText(path)
    if text == nil then
        error("the shot file could not be read", 0)
    end
    return text
end)

Api.putShotXml = guard(function(n, xmlText, force)
    inGame()
    if type(xmlText) ~= "string" or xmlText:match("^%s*$") then
        error("empty shot text", 0)
    end
    local index = liveIndex()
    local file, i
    if n == nil then
        file, i = St.newFileName(index), #index.files + 1
    else
        file, i = fileOf(n)
    end
    flush()
    St.ensureDirectory()
    if not writeText(St.getPath(Api.TEMP_FILE), xmlText) then
        error("the temporary file could not be written", 0)
    end
    local shot, problems = St.loadChecked(Api.TEMP_FILE)
    if deleteFile ~= nil then
        pcall(deleteFile, St.getPath(Api.TEMP_FILE))
    end
    if shot == nil then
        error("the shot could not be loaded: " .. table.concat(problems, "; "), 0)
    end
    if #problems > 0 and not force then
        error("the shot has errors, nothing was saved: " .. table.concat(problems, "; "), 0)
    end
    local before = n ~= nil and fileExists(St.getPath(file)) and St.load(file) or S.new(shotName(i))
    local given = shot.name
    shot.file = file
    shot.name = (given ~= nil and given ~= "" and given ~= Api.TEMP_FILE) and given:sub(1, Api.NAME_MAX) or shotName(i)
    if not St.save(shot) then
        error("the shot could not be saved", 0)
    end
    appendHistory(file, before, shot)
    if n == nil then
        index.files[i] = file
        St.saveIndex(index)
    end
    local scr = screen()
    if isOpen(scr) then
        if scr.index.active == i then
            scr:stopActors()
            scr:openShot(i)
        end
    elseif scr ~= nil then
        scr.shot, scr.index = nil, nil
    end
    return i, { warnings = Api.missingVehicles(shot, W.find), problems = problems, file = file }
end)

Api.openShot = guard(function(n)
    local _, i = fileOf(n)
    local scr = ensureEditor()
    if scr.index.active ~= i then
        scr:stopActors()
        scr:saveAll()
        scr:openShot(i)
    end
    return i
end)

Api.closeEditor = guard(function()
    local open = isOpen(screen())
    if open then
        g_gui:showGui("")
    end
    return open
end)

Api.play = guard(function(n)
    local ok, i = Api.openShot(n)
    if not ok then
        error(i, 0)
    end
    local scr = screen()
    if scr.playing then
        scr:stopPlayback()
    end
    local blocked = scr:getPlayBlockText()
    if blocked ~= nil then
        error(blocked, 0)
    end
    scr.menu, scr.palette = nil, nil
    scr:startPlayback(0)
    if not scr.playing then
        error("playback did not start", 0)
    end
    return i
end)

Api.stop = guard(function()
    local scr = screen()
    local was = scr ~= nil and scr.playing == true
    if was then
        scr:stopPlayback()
    end
    return was
end)

function Api.status()
    local st = { playing = false, shot = nil, t = 0, duration = 0, editorOpen = false, prerollLeft = 0 }
    pcall(function()
        local scr = screen()
        st.editorOpen = isOpen(scr)
        if scr ~= nil and scr.shot ~= nil and scr.index ~= nil then
            st.shot = scr.index.active
            st.playing = st.editorOpen and scr.playing == true
            st.t = st.playing and scr.playTime or scr.playhead or 0
            st.duration = st.playing and scr.playEnd or S.duration(scr.shot)
            st.prerollLeft = st.playing and math.max(0, scr.prerollLeft or 0) or 0
        end
    end)
    return true, st
end

Api.reset = guard(function(n)
    local ok, i = Api.openShot(n)
    if not ok then
        error(i, 0)
    end
    local scr = screen()
    if scr.playing then
        scr:stopPlayback()
    end
    scr.menu, scr.palette = nil, nil
    scr:resetActors(false)
    scr:setPlayhead(0, scr.topdown == nil)
    scr:showActorStates(0)
    return i
end)

Api.poseAt = guard(function(n, t)
    inGame()
    local shot, i = shotFor(n)
    t = tonumber(t)
    if t == nil then
        error("time t is not a number", 0)
    end
    if #shot.segments == 0 then
        error("the shot has no camera blocks", 0)
    end
    -- bez editoru: stejný výpočet jako v editoru (plánovaná poloha vozidel), jen nad záběrem bez obrazovky
    local ev = setmetatable({ shot = shot, targetFocal = 35, targetFilters = {}, heldPoses = {} }, { __index = CinemaEditorScreen })
    local x, y, z, q, focal = ev:evaluatePose(math.max(0, t), nil)
    if x == nil then
        error("pose cannot be computed: the camera target (vehicle) is not in the game", 0)
    end
    return { x = x, y = y, z = z, qx = q[1], qy = q[2], qz = q[3], qw = q[4], focal = focal, shot = i, t = math.max(0, t) }
end)

Api.setCameraPose = guard(function(pose)
    local p, why = Api.normalizePose(pose)
    if p == nil then
        error(why, 0)
    end
    local scr = ensureEditor()
    if scr.playing then
        scr:stopPlayback()
    end
    if scr.topdown ~= nil then
        scr:exitTopdown()
    end
    scr.menu, scr.palette = nil, nil
    scr:setClean(true)
    scr.vel = { 0, 0, 0 }
    scr.targetFocal = p.focal
    CinemaCamera.setPose(scr.cam, p.x, p.y, p.z, p.q, p.focal)
    return true
end)

Api.pinActor = guard(function(n, uid)
    inGame()
    local v = uid ~= nil and W.find(uid) or nil
    if v == nil then
        error(string.format("vehicle %s is not in the game", tostring(uid)), 0)
    end
    local root = W.rootOf(v)
    local rootUid = W.uid(root)
    local file, i = fileOf(n)
    local scr = screen()
    local live = isOpen(scr) and scr.shot ~= nil and scr.index.active == i
    local shot = live and scr.shot or St.load(file) or S.new(file)
    local before = S.clone(shot)
    if live then
        scr:pushUndo()
    end
    local actor
    for _, a in ipairs(shot.actors) do
        local first = a.start ~= nil and a.start.entries[1] or nil
        if first ~= nil and first.uid == rootUid then
            actor = a
        end
    end
    if actor ~= nil then
        actor.start = W.captureStart(root)
        if #actor.points <= 1 then
            local x, _, z = getWorldTranslation(root.rootNode)
            actor.points = { { x, z } }
        end
    else
        actor = CinemaEditorScreen.newVehicleActor(root)
        table.insert(shot.actors, actor)
    end
    S.touch(shot)
    local id = S.actorId(shot, actor)
    if live then
        scr.actorRt = {}
        scr:syncDrivers()
        scr:markDirty()
        scr:save(true)
    else
        shot.file = file
        if not St.save(shot) then
            error("the shot could not be saved", 0)
        end
        appendHistory(file, before, shot)
        if scr ~= nil and not isOpen(scr) then
            scr.shot, scr.index = nil, nil
        end
    end
    return id
end)

---------------------------------------------------------------------------------------------------
-- místa

Api.getPlaces = guard(function()
    inGame()
    return St.loadPlaces()
end)

Api.setPlace = guard(function(name, p)
    inGame()
    local place, why = Api.makePlace(name, p, W.terrainY)
    if place == nil then
        error(why, 0)
    end
    local list = St.loadPlaces()
    local created = St.upsertPlace(list, place)
    if not St.savePlaces(list) then
        error("places.xml could not be saved", 0)
    end
    return { name = place.name, created = created }
end)

Api.deletePlace = guard(function(name)
    inGame()
    local list = St.loadPlaces()
    local removed = St.removePlace(list, name)
    if removed and not St.savePlaces(list) then
        error("places.xml could not be saved", 0)
    end
    return removed
end)

rawset(_G, "CinemaStudioApi", Api)
