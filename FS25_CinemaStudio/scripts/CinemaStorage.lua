-- Ukládání záběrů do modSettings/FS25_CinemaStudio/<savegame>/: <soubor>.xml na záběr a index.xml s pořadím.
-- Záběr patří k savegame: vozidla (míření, režim kolem objektu, herci) se odkazují přes uniqueId a sedí jen v savu, kde
-- ta vozidla existují, a každý save má jiné scény.

CinemaStorage = CinemaStorage or {}
local St = CinemaStorage
local S = CinemaShot
local M = CinemaMath

St.ROOT = "cinemaShot"
St.INDEX_ROOT = "cinemaShots"
-- 5: chůze postavy rychlostí hráče (4 m/s); ve 4 šla 1,5 m/s, tedy dnešní pomalou chůzí
St.FORMAT = 5

-- Při kontrolovaném načtení (St.loadChecked) se sem sbírá, co načtení zahodilo nebo nepochopilo.
local problems = nil

local function problem(fmt, ...)
    if problems ~= nil then
        problems[#problems + 1] = string.format(fmt, ...)
    end
end

local function safeName(name)
    return (tostring(name):gsub("[^%w%-_]", "_"))
end

function St.getDirectory()
    local name = "savegame"
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if info ~= nil and info.savegameIndex ~= nil then
        name = "savegame" .. tostring(info.savegameIndex)
    elseif info ~= nil and info.mapId ~= nil then
        name = info.mapId
    end
    return getUserProfileAppPath() .. "modSettings/FS25_CinemaStudio/" .. safeName(name) .. "/"
end

function St.getPath(file)
    return St.getDirectory() .. safeName(file) .. ".xml"
end

local function ensureDirectory()
    createFolder(getUserProfileAppPath() .. "modSettings/")
    createFolder(getUserProfileAppPath() .. "modSettings/FS25_CinemaStudio/")
    createFolder(St.getDirectory())
end
St.ensureDirectory = ensureDirectory

-- Plochá tabulka čísel / řetězců / pravdivostí jako atributy prvku.
local function writeFlat(xmlFile, key, t)
    for k, v in pairs(t) do
        if type(k) == "string" then
            if type(v) == "number" then
                xmlFile:setFloat(key .. "#" .. k, v)
            elseif type(v) == "string" then
                xmlFile:setString(key .. "#" .. k, "s:" .. v)
            elseif type(v) == "boolean" then
                xmlFile:setString(key .. "#" .. k, v and "b:1" or "b:0")
            end
        end
    end
end

local function readFlat(xmlFile, key, names)
    local t = {}
    for _, name in ipairs(names) do
        local raw = xmlFile:getString(key .. "#" .. name)
        if raw ~= nil then
            if raw:sub(1, 2) == "s:" then
                t[name] = raw:sub(3)
            elseif raw:sub(1, 2) == "b:" then
                t[name] = raw:sub(3) == "1"
            else
                t[name] = tonumber(raw) or raw
            end
        end
    end
    return t
end

St.TRACK_FIELDS = { "mode", "target", "duration", "radius", "radius2", "height", "height2", "dist", "dist2", "laps", "dir",
    "side", "lead", "relAngle", "ease", "easeIn", "easeOut", "angle0", "lookHeight", "camX", "camY", "camZ", "yaw", "pitch", "focal", "focal2", "dist0", "autoZoom", "smooth", "blend",
    "rampIn", "rampOut", "lag", "relAngle2", "passAt", "rotate", "target2", "margin", "elev", "shake", "variant", "mountPath", "camIndex",
    "ox", "oy", "oz", "fx", "fy", "fz", "ux", "uy", "uz", "shiftX", "shiftY", "shiftZ", "aimYaw", "aimPitch" }
St.START_FIELDS = { "uid", "x", "y", "z", "rx", "ry", "rz" }
St.JOINT_FIELDS = { "parent", "child", "joint", "input" }
St.PROP_FIELDS = { "kind", "name", "uid", "x", "y", "z", "rx", "ry", "rz", "xmlFilename", "fillType", "fillLevel", "variation", "wrap",
    "wrapDiffuse", "wrapNormal", "amount", "radius", "field", "fruit", "growth", "ground", "sprayType", "sprayLevel", "lime", "plow",
    "roller", "stubble", "weed", "stone", "water", "clear", "windrow", "windrowAmount", "windrowLines", "windrowSource", "windrowSpacing",
    "rider", "lx", "ly", "lz", "lry" }

local function toNetwork(path)
    return path ~= nil and NetworkUtil ~= nil and NetworkUtil.convertToNetworkFilename(path) or path
end

local function fromNetwork(path)
    return path ~= nil and NetworkUtil ~= nil and NetworkUtil.convertFromNetworkFilename(path) or path
end

-- Souprava (start herce nebo předmětu): články, zapřažení a stav.
local function writeStart(xmlFile, key, start)
    for j, e in ipairs(start.entries or {}) do
        writeFlat(xmlFile, string.format("%s.start(%d)", key, j - 1), e)
    end
    for j, e in ipairs(start.joints or {}) do
        writeFlat(xmlFile, string.format("%s.joint(%d)", key, j - 1), e)
    end
    local names = {}
    for name in pairs(start.states or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    for j, name in ipairs(names) do
        local k2 = string.format("%s.state(%d)", key, j - 1)
        xmlFile:setString(k2 .. "#key", name)
        local value = start.states[name]
        xmlFile:setString(k2 .. "#value", type(value) == "number" and tostring(math.floor(value * 10000 + 0.5) / 10000) or tostring(value))
    end
end

local function readStart(xmlFile, key, start)
    xmlFile:iterate(key .. ".start", function(_, k2)
        start.entries[#start.entries + 1] = readFlat(xmlFile, k2, St.START_FIELDS)
    end)
    xmlFile:iterate(key .. ".joint", function(_, k2)
        start.joints[#start.joints + 1] = readFlat(xmlFile, k2, St.JOINT_FIELDS)
    end)
    xmlFile:iterate(key .. ".state", function(_, k2)
        local name, raw = xmlFile:getString(k2 .. "#key"), xmlFile:getString(k2 .. "#value")
        if name ~= nil and raw ~= nil then
            start.states = start.states or {}
            start.states[name] = tonumber(raw) or raw
        else
            problem("state %s: missing key or value", k2)
        end
    end)
end

-- Akce herce nebo objektu ve světě; sub (skupina světel = číslo, výroba = text) se ukládá i s typem.
local function writeAction(xmlFile, k2, action)
    xmlFile:setFloat(k2 .. "#t", action.t)
    xmlFile:setString(k2 .. "#kind", action.kind)
    xmlFile:setInt(k2 .. "#value", action.value or 1)
    xmlFile:setInt(k2 .. "#entry", action.entry or 0)
    if action.vehicle ~= nil then
        xmlFile:setString(k2 .. "#vehicle", action.vehicle)
    end
    if action.anim ~= nil then
        xmlFile:setString(k2 .. "#anim", action.anim)
    end
    if action.leg ~= nil then
        xmlFile:setInt(k2 .. "#leg", action.leg)
    end
    if action.dur ~= nil then
        xmlFile:setFloat(k2 .. "#dur", action.dur)
    end
    if action.sub ~= nil then
        xmlFile:setString(k2 .. "#sub", (type(action.sub) == "number" and "n:" or "s:") .. tostring(action.sub))
    end
    if action.subLabel ~= nil then
        xmlFile:setString(k2 .. "#subLabel", action.subLabel)
    end
    if action.items ~= nil then
        xmlFile:setString(k2 .. "#items", action.items)
    end
    if action.link ~= nil then
        writeFlat(xmlFile, k2 .. ".link", action.link)
    end
    if action.carry ~= nil then
        writeFlat(xmlFile, k2 .. ".carry", action.carry)
    end
end

St.LINK_FIELDS = { "source", "pond", "port", "target", "x", "y", "z", "dx", "dz", "valve" }
St.CARRY_FIELDS = { "kind", "uid", "name", "r", "x", "y", "z", "rx", "ry", "rz", "rider", "lx", "ly", "lz", "lry", "path" }

-- Akce z klíče k2, nebo nil u neznámého druhu.
local function readAction(xmlFile, k2)
    local t, kind = xmlFile:getFloat(k2 .. "#t"), xmlFile:getString(k2 .. "#kind")
    local def = kind ~= nil and CinemaActions.KINDS[kind] or nil
    if t == nil or def == nil or def.stateOnly then
        problem("action %s: %s", k2, t == nil and "missing time (t)" or "unknown kind " .. tostring(kind))
        return nil
    end
    local action = { t = t, kind = kind, value = xmlFile:getInt(k2 .. "#value", 1), entry = xmlFile:getInt(k2 .. "#entry", 0) }
    action.vehicle, action.anim = xmlFile:getString(k2 .. "#vehicle"), xmlFile:getString(k2 .. "#anim")
    action.items = xmlFile:getString(k2 .. "#items")
    action.actor = xmlFile:getInt(k2 .. "#actor")
    action.leg = xmlFile:getInt(k2 .. "#leg")
    if kind == "canisters" and action.value == 1 then
        local list, why = CinemaActions.parseCanisters(action.items)
        if list == nil then
            problem("action %s: canisters: %s", k2, why)
        end
    end
    local sub = xmlFile:getString(k2 .. "#sub")
    if sub ~= nil then
        action.sub = sub:sub(1, 2) == "n:" and tonumber(sub:sub(3)) or sub:sub(3)
    end
    action.subLabel = xmlFile:getString(k2 .. "#subLabel")
    local link = readFlat(xmlFile, k2 .. ".link", St.LINK_FIELDS)
    if next(link) ~= nil then
        action.link = link
    end
    local carry = readFlat(xmlFile, k2 .. ".carry", St.CARRY_FIELDS)
    if next(carry) ~= nil then
        action.carry = carry
    end
    CinemaActions.setDuration(action, xmlFile:getFloat(k2 .. "#dur"))
    return action
end

St.OBJECT_FIELDS = { "id", "type", "name", "uid", "saveId", "x", "z" }

local function numbers(text, count)
    if text == nil then
        return nil
    end
    local out = {}
    for v in text:gmatch("[^%s]+") do
        out[#out + 1] = tonumber(v)
    end
    if #out ~= count then
        return nil
    end
    for i = 1, count do
        if out[i] == nil then
            return nil
        end
    end
    return out
end

-- Bod trasy "x z [kmh|-] [pauza|-] [r] [x<id>[m]] [a<natočení °>]" → { x, z, kmh?, wait?, reverse?, yaw?, exit?, manual? },
-- nebo nil, když je zápis vadný. x = výstup postavy z vozidla (začátek části trasy id), m = ručně posunutý bod výstupu.
function St.parsePoint(text)
    local tokens = {}
    for token in text:gmatch("[^%s]+") do
        tokens[#tokens + 1] = token
    end
    local floor = nil
    if #tokens > 2 and tokens[#tokens]:sub(1, 1) == "h" then
        floor = tonumber(tokens[#tokens]:sub(2))
        if floor == nil then
            return nil
        end
        tokens[#tokens] = nil
    end
    local yaw = nil
    if #tokens > 2 and tokens[#tokens]:sub(1, 1) == "a" then
        yaw = tonumber(tokens[#tokens]:sub(2))
        if yaw == nil then
            return nil
        end
        tokens[#tokens] = nil
    end
    local exit, manual = nil, nil
    if #tokens > 2 then
        exit, manual = tokens[#tokens]:match("^x(%d*)(m?)$")
    end
    if exit ~= nil then
        exit = tonumber(exit) or true
        tokens[#tokens] = nil
    end
    local x, z = tonumber(tokens[1]), tonumber(tokens[2])
    if x == nil or z == nil or #tokens > 5 then
        return nil
    end
    local p = { x, z }
    if tokens[3] ~= nil then
        p[3] = tonumber(tokens[3])
        if p[3] == nil and tokens[3] ~= "-" then
            return nil
        end
    end
    if tokens[4] ~= nil then
        p[4] = tonumber(tokens[4])
        if p[4] == nil and tokens[4] ~= "-" then
            return nil
        end
    end
    if tokens[5] ~= nil then
        if tokens[5] ~= "r" then
            return nil
        end
        p[5] = true
    end
    if yaw ~= nil then
        p[6] = math.rad(yaw)
    end
    p[7] = exit or nil
    p[8] = manual == "m" or nil
    p[9] = floor
    return p
end

-- Kanály (průběhy hodnot v čase): prvky <channel id hidden points="t v mode;…"/> pod base.
local function writeChannels(xmlFile, base, curves)
    local i = 0
    for id, ch in pairs(curves or {}) do
        if CinemaChannels.hasPoints(ch) or ch.hidden then
            local key = string.format("%s.channel(%d)", base, i)
            i = i + 1
            xmlFile:setString(key .. "#id", id)
            if ch.hidden then
                xmlFile:setBool(key .. "#hidden", true)
            end
            local pts = {}
            for _, p in ipairs(ch.points or {}) do
                pts[#pts + 1] = string.format("%.3f %.4f %s", p.t, p.v, p.mode or "linear")
            end
            xmlFile:setString(key .. "#points", table.concat(pts, ";"))
        end
    end
end

local function readChannels(xmlFile, base)
    local curves = nil
    xmlFile:iterate(base .. ".channel", function(_, key)
        local id = xmlFile:getString(key .. "#id")
        if id ~= nil then
            local ch = CinemaChannels.new()
            ch.hidden = xmlFile:getBool(key .. "#hidden", false) or nil
            for item in (xmlFile:getString(key .. "#points") or ""):gmatch("[^;]+") do
                local t, v, mode = item:match("^%s*(%S+)%s+(%S+)%s+(%S+)%s*$")
                t, v = tonumber(t), tonumber(v)
                if t ~= nil and v ~= nil then
                    ch.points[#ch.points + 1] = { t = t, v = v, mode = mode }
                end
            end
            table.sort(ch.points, function(a, b) return a.t < b.t end)
            curves = curves or {}
            curves[id] = ch
        end
    end)
    return curves
end

-- Zapíše záběr (nebo jeho snímek) do prvku root souboru xmlFile.
local function writeShot(xmlFile, root, shot)
    xmlFile:setInt(root .. "#format", St.FORMAT)
    xmlFile:setString(root .. "#name", shot.name)
    xmlFile:setFloat(root .. "#preroll", shot.preroll)
    if shot.endMark ~= nil then
        xmlFile:setFloat(root .. "#endMark", shot.endMark)
    end
    xmlFile:setFloat(root .. "#bank", shot.bank or 0)
    xmlFile:setInt(root .. "#shake", shot.shake or 0)
    if shot.focusRow then
        xmlFile:setBool(root .. "#focusRow", true)
    end
    if shot.rowOrder ~= nil then
        xmlFile:setString(root .. "#rows", table.concat(shot.rowOrder, ";"))
    end
    if shot.env ~= nil then
        if shot.env.hour ~= nil then
            xmlFile:setFloat(root .. "#envHour", shot.env.hour)
        end
        if shot.env.season ~= nil then
            xmlFile:setString(root .. "#envSeason", shot.env.season)
        end
        if shot.env.weather ~= nil then
            xmlFile:setString(root .. "#envWeather", shot.env.weather)
        end
    end
    S.syncCamera(shot)
    xmlFile:setInt(root .. "#camera", shot.camIndex)
    for ci, cam in ipairs(shot.cameras) do
        local base = string.format("%s.camera(%d)", root, ci - 1)
        if cam.name ~= nil then
            xmlFile:setString(base .. "#name", cam.name)
        end
        if cam.camColor ~= nil then
            xmlFile:setInt(base .. "#color", cam.camColor)
        end
        if cam.camHidden then
            xmlFile:setBool(base .. "#hidden", true)
        end
        for i, seg in ipairs(cam.segments or {}) do
            local key = string.format("%s.segment(%d)", base, i - 1)
            xmlFile:setInt(key .. "#id", seg.id)
            xmlFile:setFloat(key .. "#t", seg.t)
            writeFlat(xmlFile, key .. ".track", seg.track)
            for j, k in ipairs(seg.track.keys or {}) do
                local kk = string.format("%s.track.key(%d)", key, j - 1)
                xmlFile:setFloat(kk .. "#t", k.t)
                xmlFile:setString(kk .. "#pos", string.format("%.4f %.4f %.4f", k.x, k.y, k.z))
                xmlFile:setString(kk .. "#rot", string.format("%.6f %.6f %.6f %.6f", k.q[1], k.q[2], k.q[3], k.q[4]))
                xmlFile:setFloat(kk .. "#focal", k.focal)
                if k.speed ~= nil then
                    xmlFile:setFloat(kk .. "#speed", k.speed)
                end
                if k.free then
                    xmlFile:setBool(kk .. "#free", true)
                end
                if k.infIn ~= nil then
                    xmlFile:setFloat(kk .. "#infIn", k.infIn)
                end
                if k.infOut ~= nil then
                    xmlFile:setFloat(kk .. "#infOut", k.infOut)
                end
                if k.hin ~= nil then
                    xmlFile:setString(kk .. "#hin", string.format("%.4f %.4f %.4f", k.hin[1], k.hin[2], k.hin[3]))
                end
                if k.hout ~= nil then
                    xmlFile:setString(kk .. "#hout", string.format("%.4f %.4f %.4f", k.hout[1], k.hout[2], k.hout[3]))
                end
                if k.aimYaw ~= nil then
                    xmlFile:setFloat(kk .. "#aimYaw", k.aimYaw)
                    xmlFile:setFloat(kk .. "#aimPitch", k.aimPitch or 0)
                end
            end
            if seg.track.marks ~= nil and #seg.track.marks > 0 then
                local marks = {}
                for _, m in ipairs(seg.track.marks) do
                    marks[#marks + 1] = string.format("%.4f %.2f %.3f", m.u, m.focal or 35, m.speed or 1)
                end
                xmlFile:setString(key .. ".track#marks", table.concat(marks, ";"))
            end
        end
        writeChannels(xmlFile, base, cam.curves)
        for i, f in ipairs(cam.focus or {}) do
            local key = string.format("%s.focus(%d)", base, i - 1)
            xmlFile:setFloat(key .. "#t", f.t)
            if f.target ~= nil then
                xmlFile:setString(key .. "#target", f.target)
            end
            xmlFile:setFloat(key .. "#height", f.height or S.FOCUS_HEIGHT)
            xmlFile:setFloat(key .. "#blend", f.blend or S.FOCUS_BLEND)
            if (f.ox or 0) ~= 0 or (f.oy or 0) ~= 0 then
                xmlFile:setString(key .. "#frame", string.format("%.4f %.4f", f.ox or 0, f.oy or 0))
            end
        end
    end
    for i, a in ipairs(shot.actors or {}) do
        local key = string.format("%s.actor(%d)", root, i - 1)
        xmlFile:setFloat(key .. "#speed", a.speed or 15)
        xmlFile:setFloat(key .. "#delay", a.delay or 0)
        if a.pinActions then
            xmlFile:setBool(key .. "#pinActions", true)
        end
        xmlFile:setString(key .. "#name", a.name or "")
        xmlFile:setInt(key .. "#id", S.actorId(shot, a))
        if a.color ~= nil then
            xmlFile:setInt(key .. "#color", a.color)
        end
        if a.driver ~= nil then
            xmlFile:setString(key .. "#driver", a.driver)
        end
        if a.hidden then
            xmlFile:setBool(key .. "#hidden", true)
        end
        if a.person ~= nil then
            xmlFile:setString(key .. "#person", a.person)
            if a.helper ~= nil then
                xmlFile:setString(key .. "#helper", a.helper)
            end
            local n = 0
            for _, name in ipairs(CinemaPerson.LOOK_CONFIGS) do
                local part = a.look ~= nil and a.look[name] or nil
                if part ~= nil and (part.item ~= nil or part.color ~= nil) then
                    local lk = string.format("%s.look(%d)", key, n)
                    xmlFile:setString(lk .. "#config", name)
                    if part.item ~= nil then
                        xmlFile:setString(lk .. "#item", part.item)
                    end
                    if part.color ~= nil then
                        xmlFile:setInt(lk .. "#color", part.color)
                    end
                    n = n + 1
                end
            end
            local ps = a.start ~= nil and a.start.person or nil
            if ps ~= nil then
                xmlFile:setString(key .. ".personStart#pose", string.format("%.3f %.3f %.3f %.4f", ps.x, ps.y, ps.z, ps.yaw))
            end
        end
        writeChannels(xmlFile, key, a.curves)
        local pts = {}
        for _, p in ipairs(a.points or {}) do
            local text = string.format("%.2f %.2f", p[1], p[2])
            if p[3] ~= nil or p[4] ~= nil or p[5] then
                text = text .. (p[3] ~= nil and string.format(" %.1f", p[3]) or " -")
            end
            if p[4] ~= nil or p[5] then
                text = text .. (p[4] ~= nil and string.format(" %.1f", p[4]) or " -")
            end
            if p[5] then
                text = text .. " r"
            end
            if p[7] then
                text = text .. " x" .. (p[7] ~= true and tostring(p[7]) or "") .. (p[8] and "m" or "")
            end
            if p[6] ~= nil then
                text = text .. string.format(" a%.1f", math.deg(p[6]))
            end
            if p[9] ~= nil then
                text = text .. string.format(" h%.2f", p[9])
            end
            pts[#pts + 1] = text
        end
        xmlFile:setString(key .. "#points", table.concat(pts, ";"))
        for j, action in ipairs(a.actions or {}) do
            writeAction(xmlFile, string.format("%s.action(%d)", key, j - 1), action)
        end
        if a.start ~= nil then
            writeStart(xmlFile, key, a.start)
        end
    end
    for i, p in ipairs(shot.props or {}) do
        local key = string.format("%s.prop(%d)", root, i - 1)
        local flat = {}
        for _, name in ipairs(St.PROP_FIELDS) do
            flat[name] = p[name]
        end
        flat.xmlFilename = toNetwork(p.xmlFilename)
        writeFlat(xmlFile, key, flat)
        if p.wrapColor ~= nil then
            xmlFile:setString(key .. "#wrapColor", string.format("%.4f %.4f %.4f %.4f", p.wrapColor[1] or 1, p.wrapColor[2] or 1,
                p.wrapColor[3] or 1, p.wrapColor[4] or 1))
        end
        if p.start ~= nil then
            writeStart(xmlFile, key, p.start)
        end
    end
    if shot.propsRow then
        xmlFile:setBool(root .. "#propsRow", true)
    end
    if shot.propsCollapsed then
        xmlFile:setBool(root .. "#propsCollapsed", true)
    end
    if shot.fieldsOn then
        xmlFile:setBool(root .. "#fieldsOn", true)
    end
    for i, obj in ipairs(shot.objects or {}) do
        local key = string.format("%s.object(%d)", root, i - 1)
        local flat = {}
        for _, name in ipairs(St.OBJECT_FIELDS) do
            flat[name] = obj[name]
        end
        writeFlat(xmlFile, key, flat)
        for j, action in ipairs(obj.actions or {}) do
            writeAction(xmlFile, string.format("%s.action(%d)", key, j - 1), action)
        end
    end
    if shot.objectsRow then
        xmlFile:setBool(root .. "#objectsRow", true)
    end
    if shot.objectsCollapsed then
        xmlFile:setBool(root .. "#objectsCollapsed", true)
    end
end

function St.save(shot)
    ensureDirectory()
    local file = shot.file or shot.name
    local xmlFile = XMLFile.create("cinemaShot", St.getPath(file), St.ROOT)
    if xmlFile == nil then
        return false
    end
    writeShot(xmlFile, St.ROOT, shot)
    xmlFile:save()
    xmlFile:delete()
    return true
end

-- K-frame Letu (i volný keyframe starého formátu): nil, když je zápis vadný.
local function readKey(xmlFile, key)
    local pos = numbers(xmlFile:getString(key .. "#pos"), 3)
    local rot = numbers(xmlFile:getString(key .. "#rot"), 4)
    local t = xmlFile:getFloat(key .. "#t")
    if pos == nil or rot == nil or t == nil then
        return nil
    end
    local k = S.newKey(t, pos[1], pos[2], pos[3], M.quatNormalize(rot), xmlFile:getFloat(key .. "#focal", 35))
    k.speed = xmlFile:getFloat(key .. "#speed")
    k.free = xmlFile:getBool(key .. "#free", false) or nil
    k.infIn = xmlFile:getFloat(key .. "#infIn")
    k.infOut = xmlFile:getFloat(key .. "#infOut")
    k.hin = numbers(xmlFile:getString(key .. "#hin"), 3)
    k.hout = numbers(xmlFile:getString(key .. "#hout"), 3)
    k.aimYaw = xmlFile:getFloat(key .. "#aimYaw")
    k.aimPitch = xmlFile:getFloat(key .. "#aimPitch")
    return k
end

-- Záběr z doby před bloky (formát do 3): volné keyframy ležely na ose samostatně, bloky režimů měly kotvy a mezi bloky
-- kamera letěla. Každý souvislý řetěz volných keyframů (bez bloku a tvrdého střihu mezi nimi) se stane Letem, kotvy
-- zmizí a blok „přesun“ se nahradí plynulým navázáním dalšího bloku.
function St.convertLegacy(shot, keys)
    S.sortSegments(shot)
    for i = #shot.segments, 1, -1 do
        if shot.segments[i].track.mode == "move" then
            local nextSeg = shot.segments[i + 1]
            if nextSeg ~= nil then
                nextSeg.track.smooth = true
            end
            table.remove(shot.segments, i)
        end
    end
    table.sort(keys, function(a, b) return a.t < b.t end)
    local function blockBetween(t0, t1)
        for _, seg in ipairs(shot.segments) do
            if seg.t < t1 and S.segmentEnd(seg) > t0 then
                return true
            end
        end
        return false
    end
    local chain, made = {}, {}
    local function flush()
        if #chain == 0 then
            return
        end
        local t0 = chain[1].t
        local track = { mode = S.FLIGHT, keys = {} }
        for _, k in ipairs(chain) do
            local c = S.newKey(k.t - t0, k.x, k.y, k.z, k.q, k.focal)
            if math.max(k.easeIn or 0, k.easeOut or 0) >= 0.5 then
                c.speed = 0
            end
            track.keys[#track.keys + 1] = c
        end
        local duration = chain[#chain].t - t0
        if duration < S.MIN_SEGMENT then
            local nextSeg = S.blockAfter(shot, t0 + 1e-6)
            local room = nextSeg ~= nil and nextSeg.t - S.MIN_GAP - t0 or S.MIN_SEGMENT
            duration = math.max(math.min(S.MIN_SEGMENT, room), S.MIN_GAP)
        end
        track.duration = duration
        made[#made + 1] = { t = t0, track = track }
        chain = {}
    end
    for _, k in ipairs(keys) do
        if k.anchor ~= nil then
            flush()
        else
            local prev = chain[#chain]
            if prev ~= nil and (prev.cut or blockBetween(prev.t, k.t)) then
                flush()
            end
            chain[#chain + 1] = k
        end
    end
    flush()
    for _, m in ipairs(made) do
        S.addSegment(shot, { id = S.nextSegmentId(shot), t = m.t, track = m.track })
    end
end

-- Načte jednu kameru do vybrané kamery záběru (živá pole shot.segments / focus); legacy = starý formát bez <camera>.
local function readCamera(xmlFile, base, shot, legacy)
    local oldKeys = {}
    xmlFile:iterate(base .. ".key", function(_, key)
        local k = readKey(xmlFile, key)
        if k ~= nil then
            k.easeIn = xmlFile:getFloat(key .. "#easeIn", 0)
            k.easeOut = xmlFile:getFloat(key .. "#easeOut", 0)
            k.cut = xmlFile:getBool(key .. "#cut", false)
            k.anchor = xmlFile:getInt(key .. "#anchor")
            oldKeys[#oldKeys + 1] = k
        end
    end)
    xmlFile:iterate(base .. ".segment", function(_, key)
        local track = readFlat(xmlFile, key .. ".track", St.TRACK_FIELDS)
        local t = xmlFile:getFloat(key .. "#t")
        if S.KEYED[track.mode] then
            track.keys = {}
            xmlFile:iterate(key .. ".track.key", function(_, kk)
                local k = readKey(xmlFile, kk)
                if k ~= nil then
                    track.keys[#track.keys + 1] = k
                end
            end)
            table.sort(track.keys, function(a, b) return a.t < b.t end)
            if #track.keys == 0 then
                track.keys = nil
                S.standToKeys(track)
            end
            if track.keys == nil then
                t = nil
            end
        end
        local rawMarks = xmlFile:getString(key .. ".track#marks")
        if rawMarks ~= nil then
            local marks = {}
            for item in rawMarks:gmatch("[^;]+") do
                local v = numbers(item, 3)
                if v ~= nil and v[1] > 0 and v[1] < 1 then
                    marks[#marks + 1] = { u = v[1], focal = v[2], speed = v[3] }
                end
            end
            table.sort(marks, function(a, b) return a.u < b.u end)
            track.marks = #marks > 0 and marks or nil
        end
        local known = track.mode == S.FLIGHT or track.mode == "move" or (track.mode ~= nil and CinemaModes.DEFAULTS[track.mode] ~= nil)
        if t ~= nil and known then
            shot.segments[#shot.segments + 1] = { id = xmlFile:getInt(key .. "#id", #shot.segments + 1), t = t, track = track }
        else
            problem("camera block %s: %s", key, not known and "unknown mode " .. tostring(track.mode) or "missing time (t) or keys")
        end
    end)
    -- záběr z verze 0.3 měl jeden režim na celou dobu: je to úsek od začátku (kotvy se dopočítají při otevření)
    if #shot.segments == 0 and legacy and xmlFile:hasProperty(base .. ".track") then
        local track = readFlat(xmlFile, base .. ".track", St.TRACK_FIELDS)
        if track.mode ~= nil and CinemaModes.DEFAULTS[track.mode] ~= nil then
            shot.segments[1] = { id = 1, t = 0, track = track }
        end
    end
    -- míření z verze 0.2 (jeden objekt na celý záběr) je bod zájmu od začátku
    local lookTarget = legacy and xmlFile:getString(base .. ".lookAt#target") or nil
    if lookTarget ~= nil then
        local i = S.setFocus(shot, 0, lookTarget, xmlFile:getFloat(base .. ".lookAt#height", S.FOCUS_HEIGHT))
        shot.focus[i].blend = 0
    end
    xmlFile:iterate(base .. ".focus", function(_, key)
        local t = xmlFile:getFloat(key .. "#t")
        if t ~= nil then
            local i = S.setFocus(shot, t, xmlFile:getString(key .. "#target"), xmlFile:getFloat(key .. "#height", S.FOCUS_HEIGHT))
            shot.focus[i].blend = xmlFile:getFloat(key .. "#blend", S.FOCUS_BLEND)
            local frame = numbers(xmlFile:getString(key .. "#frame"), 2)
            if frame ~= nil then
                shot.focus[i].ox, shot.focus[i].oy = frame[1], frame[2]
            end
        end
    end)
    St.convertLegacy(shot, oldKeys)
end

-- Přečte záběr (nebo jeho snímek) z prvku root souboru xmlFile.
local function readShot(xmlFile, root, file)
    local format = xmlFile:getInt(root .. "#format", St.FORMAT)
    local shot = S.new(xmlFile:getString(root .. "#name", file))
    shot.file = file
    shot.preroll = xmlFile:getFloat(root .. "#preroll", S.DEFAULT_PREROLL)
    shot.endMark = xmlFile:getFloat(root .. "#endMark", nil)
    shot.bank = xmlFile:getFloat(root .. "#bank", 0)
    shot.shake = xmlFile:getInt(root .. "#shake", 0)
    local env = {
        hour = xmlFile:getFloat(root .. "#envHour", nil),
        season = xmlFile:getString(root .. "#envSeason", nil),
        weather = xmlFile:getString(root .. "#envWeather", nil),
    }
    if CinemaEnvironment.SEASON_PERIOD[env.season] == nil then
        env.season = nil
    end
    shot.env = next(env) ~= nil and env or nil
    shot.focusRow = xmlFile:getBool(root .. "#focusRow", false) or nil
    local rows = xmlFile:getString(root .. "#rows")
    if rows ~= nil then
        shot.rowOrder = {}
        for key in rows:gmatch("[^;]+") do
            shot.rowOrder[#shot.rowOrder + 1] = key
        end
    end
    if xmlFile:hasProperty(root .. ".camera(0)") then
        local first = true
        xmlFile:iterate(root .. ".camera", function(_, base)
            if not first then
                S.addCamera(shot)
            end
            first = false
            shot.cameras[shot.camIndex].name = xmlFile:getString(base .. "#name")
            shot.camColor = xmlFile:getInt(base .. "#color")
            shot.camHidden = xmlFile:getBool(base .. "#hidden", false) or nil
            shot.curves = readChannels(xmlFile, base)
            readCamera(xmlFile, base, shot, false)
        end)
        S.setCamera(shot, M.clamp(xmlFile:getInt(root .. "#camera", 1), 1, #shot.cameras))
    else
        shot.camColor = xmlFile:getInt(root .. "#camColor")
        readCamera(xmlFile, root, shot, true)
    end
    xmlFile:iterate(root .. ".actor", function(_, key)
        local a = { speed = xmlFile:getFloat(key .. "#speed", 15), delay = xmlFile:getFloat(key .. "#delay", 0),
            name = xmlFile:getString(key .. "#name", ""), color = xmlFile:getInt(key .. "#color"),
            driver = xmlFile:getString(key .. "#driver"), hidden = xmlFile:getBool(key .. "#hidden", false) or nil,
            pinActions = xmlFile:getBool(key .. "#pinActions", false) or nil, points = {},
            start = { entries = {}, joints = {} } }
        a.curves = readChannels(xmlFile, key)
        a.id = xmlFile:getInt(key .. "#id")
        a.person = xmlFile:getString(key .. "#person")
        a.helper = xmlFile:getString(key .. "#helper")
        local n = 0
        while xmlFile:hasProperty(string.format("%s.look(%d)", key, n)) do
            local lk = string.format("%s.look(%d)", key, n)
            local name = xmlFile:getString(lk .. "#config")
            if name ~= nil then
                a.look = a.look or {}
                a.look[name] = { item = xmlFile:getString(lk .. "#item"), color = xmlFile:getInt(lk .. "#color") }
            end
            n = n + 1
        end
        local pose = numbers(xmlFile:getString(key .. ".personStart#pose"), 4)
        if pose ~= nil then
            a.start.person = { x = pose[1], y = pose[2], z = pose[3], yaw = pose[4] }
        end
        for pair in (xmlFile:getString(key .. "#points", "")):gmatch("[^;]+") do
            local p = St.parsePoint(pair)
            if p ~= nil then
                a.points[#a.points + 1] = p
            else
                problem("actor %s: invalid route point \"%s\"", key, pair)
            end
        end
        xmlFile:iterate(key .. ".action", function(_, k2)
            local action = readAction(xmlFile, k2)
            if action ~= nil then
                CinemaActions.add(a, action)
            end
        end)
        readStart(xmlFile, key, a.start)
        if a.person ~= nil and CinemaPerson ~= nil then
            if format < 5 then
                CinemaPerson.keepOldWalk(a)
            end
            CinemaPerson.snapGaits(a)
        end
        shot.actors[#shot.actors + 1] = a
    end)
    xmlFile:iterate(root .. ".prop", function(_, key)
        local p = readFlat(xmlFile, key, St.PROP_FIELDS)
        if p.kind ~= nil then
            p.xmlFilename = fromNetwork(p.xmlFilename)
            local color = numbers(xmlFile:getString(key .. "#wrapColor"), 4)
            p.wrapColor = color
            if p.kind == "vehicle" then
                p.start = { entries = {}, joints = {} }
                readStart(xmlFile, key, p.start)
            end
            shot.props[#shot.props + 1] = p
        else
            problem("prop %s: missing kind", key)
        end
    end)
    for _, a in ipairs(shot.actors) do
        if CinemaPerson ~= nil and CinemaPerson.convertLegacy ~= nil then
            CinemaPerson.convertLegacy(a, shot.actors)
        end
        S.actorId(shot, a)
    end
    for _, a in ipairs(shot.actors) do
        for _, action in ipairs(a.actions or {}) do
            if action.actor ~= nil then
                local target = S.actorById(shot, action.actor)
                local first = target ~= nil and target.start ~= nil and target.start.entries[1] or nil
                if first ~= nil and first.uid ~= nil then
                    action.vehicle = first.uid
                else
                    problem("action %s of actor %s: actor %d does not exist or has no vehicle", action.kind, tostring(a.name), action.actor)
                end
                action.actor = nil
            end
            if action.kind == "attach" and action.value == 1 and action.vehicle == nil then
                problem("attach action of actor %s: missing trailer (vehicle or actor)", tostring(a.name))
            end
        end
    end
    shot.propsRow = xmlFile:getBool(root .. "#propsRow", false) or nil
    shot.propsCollapsed = xmlFile:getBool(root .. "#propsCollapsed", false) or nil
    shot.fieldsOn = xmlFile:getBool(root .. "#fieldsOn", false) or nil
    xmlFile:iterate(root .. ".object", function(_, key)
        local obj = readFlat(xmlFile, key, St.OBJECT_FIELDS)
        if obj.type ~= nil then
            obj.actions = {}
            xmlFile:iterate(key .. ".action", function(_, k2)
                local action = readAction(xmlFile, k2)
                if action ~= nil then
                    CinemaActions.add(obj, action)
                end
            end)
            shot.objects[#shot.objects + 1] = obj
        else
            problem("object %s: missing type", key)
        end
    end)
    shot.objectsRow = xmlFile:getBool(root .. "#objectsRow", false) or nil
    shot.objectsCollapsed = xmlFile:getBool(root .. "#objectsCollapsed", false) or nil
    S.touch(shot)
    return shot
end

-- Vrací záběr, nebo nil, když soubor neexistuje.
function St.load(file)
    local path = St.getPath(file)
    if not fileExists(path) then
        return nil
    end
    local xmlFile = XMLFile.load("cinemaShot", path)
    if xmlFile == nil then
        return nil
    end
    local shot = readShot(xmlFile, St.ROOT, file)
    xmlFile:delete()
    return shot
end

-- Jako St.load, ale se seznamem toho, co načtení zahodilo nebo nepochopilo (neznámý druh akce, vadný bod trasy…):
-- záběr, problémy. Bez záběru (soubor chybí, není XML nebo to není záběr) vrací nil a problémy s důvodem.
function St.loadChecked(file)
    local path = St.getPath(file)
    if not fileExists(path) then
        return nil, { "the shot file does not exist" }
    end
    local xmlFile = XMLFile.load("cinemaShot", path)
    if xmlFile == nil then
        return nil, { "the file is not valid XML" }
    end
    if not xmlFile:hasProperty(St.ROOT) then
        xmlFile:delete()
        return nil, { string.format("the root element is not <%s>", St.ROOT) }
    end
    if xmlFile:getInt(St.ROOT .. "#format", St.FORMAT) > St.FORMAT then
        xmlFile:delete()
        return nil, { string.format("format %d is newer than the supported %d", xmlFile:getInt(St.ROOT .. "#format"), St.FORMAT) }
    end
    problems = {}
    local ok, shot = pcall(readShot, xmlFile, St.ROOT, file)
    local found = problems
    problems = nil
    xmlFile:delete()
    if not ok then
        return nil, { tostring(shot) }
    end
    return shot, found
end

---------------------------------------------------------------------------------------------------
-- pojmenovaná místa savegame: places.xml se záznamy { name, x, y, z, yaw, note }

St.PLACES_ROOT = "cinemaPlaces"
St.PLACES_FILE = "places"

function St.loadPlaces()
    local list = {}
    local path = St.getPath(St.PLACES_FILE)
    if not fileExists(path) then
        return list
    end
    local xmlFile = XMLFile.load("cinemaPlaces", path)
    if xmlFile == nil then
        return list
    end
    xmlFile:iterate(St.PLACES_ROOT .. ".place", function(_, key)
        local name = xmlFile:getString(key .. "#name")
        local x, y, z = xmlFile:getFloat(key .. "#x"), xmlFile:getFloat(key .. "#y"), xmlFile:getFloat(key .. "#z")
        if name ~= nil and x ~= nil and y ~= nil and z ~= nil then
            list[#list + 1] = { name = name, x = x, y = y, z = z, yaw = xmlFile:getFloat(key .. "#yaw", 0), note = xmlFile:getString(key .. "#note") }
        end
    end)
    xmlFile:delete()
    return list
end

function St.savePlaces(list)
    ensureDirectory()
    local xmlFile = XMLFile.create("cinemaPlaces", St.getPath(St.PLACES_FILE), St.PLACES_ROOT)
    if xmlFile == nil then
        return false
    end
    for i, p in ipairs(list) do
        local key = string.format("%s.place(%d)", St.PLACES_ROOT, i - 1)
        xmlFile:setString(key .. "#name", p.name)
        xmlFile:setFloat(key .. "#x", p.x)
        xmlFile:setFloat(key .. "#y", p.y)
        xmlFile:setFloat(key .. "#z", p.z)
        xmlFile:setFloat(key .. "#yaw", p.yaw or 0)
        if p.note ~= nil and p.note ~= "" then
            xmlFile:setString(key .. "#note", p.note)
        end
    end
    xmlFile:save()
    xmlFile:delete()
    return true
end

-- Vloží místo, nebo přepíše místo stejného jména; seznam zůstane seřazený podle jména. Vrací true, když bylo nové.
function St.upsertPlace(list, place)
    for i, p in ipairs(list) do
        if p.name == place.name then
            list[i] = place
            return false
        end
    end
    list[#list + 1] = place
    table.sort(list, function(a, b) return a.name < b.name end)
    return true
end

function St.removePlace(list, name)
    for i, p in ipairs(list) do
        if p.name == name then
            table.remove(list, i)
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------------------------------
-- historie úprav záběru: <záběr>_history.xml se záznamy { time, snap }, snap je celý stav záběru před krokem

St.HISTORY_ROOT = "cinemaHistory"

function St.getHistoryPath(file)
    return St.getDirectory() .. safeName(file) .. "_history.xml"
end

function St.saveHistory(file, entries)
    ensureDirectory()
    local xmlFile = XMLFile.create("cinemaHistory", St.getHistoryPath(file), St.HISTORY_ROOT)
    if xmlFile == nil then
        return false
    end
    for i, e in ipairs(entries) do
        local base = string.format("%s.entry(%d)", St.HISTORY_ROOT, i - 1)
        xmlFile:setString(base .. "#time", string.format("%d", e.time))
        writeShot(xmlFile, base .. ".shot", e.snap)
    end
    xmlFile:save()
    xmlFile:delete()
    return true
end

function St.loadHistory(file)
    local entries = {}
    local path = St.getHistoryPath(file)
    if not fileExists(path) then
        return entries
    end
    local xmlFile = XMLFile.load("cinemaHistory", path)
    if xmlFile == nil then
        return entries
    end
    xmlFile:iterate(St.HISTORY_ROOT .. ".entry", function(_, base)
        local time = tonumber(xmlFile:getString(base .. "#time"))
        if time ~= nil then
            entries[#entries + 1] = { time = time, snap = readShot(xmlFile, base .. ".shot", file) }
        end
    end)
    xmlFile:delete()
    return entries
end

---------------------------------------------------------------------------------------------------
-- seznam záběrů

-- { files = {"shot1", ...}, active = index, counter = n }
function St.loadIndex()
    local index = { files = {}, active = 1, counter = 0 }
    local path = St.getPath("index")
    if fileExists(path) then
        local xmlFile = XMLFile.load("cinemaIndex", path)
        if xmlFile ~= nil then
            index.active = xmlFile:getInt(St.INDEX_ROOT .. "#active", 1)
            index.counter = xmlFile:getInt(St.INDEX_ROOT .. "#counter", 0)
            xmlFile:iterate(St.INDEX_ROOT .. ".shot", function(_, key)
                local file = xmlFile:getString(key .. "#file")
                if file ~= nil then
                    index.files[#index.files + 1] = file
                end
            end)
            xmlFile:delete()
        end
    end
    -- záběr z verze 0.1 (bez indexu)
    if #index.files == 0 and fileExists(St.getPath("default")) then
        index.files[1] = "default"
    end
    index.active = M.clamp(index.active, 1, math.max(#index.files, 1))
    return index
end

function St.saveIndex(index)
    ensureDirectory()
    local xmlFile = XMLFile.create("cinemaIndex", St.getPath("index"), St.INDEX_ROOT)
    if xmlFile == nil then
        return false
    end
    xmlFile:setInt(St.INDEX_ROOT .. "#active", index.active)
    xmlFile:setInt(St.INDEX_ROOT .. "#counter", index.counter)
    for i, file in ipairs(index.files) do
        xmlFile:setString(string.format("%s.shot(%d)#file", St.INDEX_ROOT, i - 1), file)
    end
    xmlFile:save()
    xmlFile:delete()
    return true
end

function St.newFileName(index)
    index.counter = index.counter + 1
    local file = "shot" .. index.counter
    while fileExists(St.getPath(file)) do
        index.counter = index.counter + 1
        file = "shot" .. index.counter
    end
    return file
end
