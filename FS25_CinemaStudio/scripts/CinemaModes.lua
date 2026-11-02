-- Živé režimy kolem objektu po vzoru DJI QuickShots. Poloha a cíl pohledu se počítají v každém snímku z aktuální
-- polohy objektu, takže fungují i u jedoucího vozidla. Výchozí úhel a vzdálenost se berou z kamery v okamžiku
-- volby režimu a ukládají se do parametrů, aby šel záběr přehrát znovu stejně. Bez herních API.

CinemaModes = CinemaModes or {}
local Mo = CinemaModes
local M = CinemaMath

Mo.ORDER = { "orbit", "dronie", "rocket", "helix", "approach", "follow", "spotlight", "boomerang", "pass", "parallel", "topdown" }

-- Režimy, které se zakládají jinak než z jednoho vozidla a kamery: připevnění na vozidlo (bod nebo kamera vozidla), pohled
-- postavy a dva cíle. Do výměny režimu bloku nepatří.
Mo.SPECIAL = { "mount", "pov", "pair" }

-- Výchozí parametry; init doplní úhel a vzdálenosti podle kamery.
-- ease = výchozí délka plynulého rozjezdu i dojezdu pohybu v sekundách (0 = rovnoměrný pohyb od první do poslední
-- chvíle); easeIn a easeOut ji přebíjí zvlášť (tažení na ose). Dohromady nejvýš délka režimu.
Mo.DEFAULTS = {
    orbit = { duration = 16, radius = 15, height = 6, laps = 1, dir = 1, ease = 3 },
    dronie = { duration = 10, dist = 6, dist2 = 60, height = 2, height2 = 35, ease = 5 },
    rocket = { duration = 10, height = 4, height2 = 70, radius = 1.5, ease = 5 },
    helix = { duration = 18, radius = 8, radius2 = 45, height = 3, height2 = 40, laps = 1, dir = 1, ease = 4 },
    approach = { duration = 10, dist = 80, dist2 = 7, height = 25, height2 = 2.5, ease = 5 },
    follow = { duration = 20, dist = 14, height = 5, side = 0, lead = 6, relAngle = 0 },
    spotlight = { duration = 15 },
    static = { duration = 8 },
    boomerang = { duration = 14, radius = 12, radius2 = 30, height = 2, height2 = 14, dir = 1, ease = 3 },
    pass = { duration = 8, side = 5, height = 0.6, passAt = 4 },
    parallel = { duration = 15, dist = 12, height = 2.5 },
    topdown = { duration = 12, height = 35, height2 = 35, rotate = true },
    mount = { duration = 10 },
    pov = { duration = 12, variant = "eyes" },
    pair = { duration = 15, margin = 4, elev = 0.45 },
}

-- Parametry, které jde v editoru měnit (+/- krok); pořadí = pořadí v menu.
Mo.ADJUSTABLE = {
    orbit = { { "radius", 2 }, { "height", 1 }, { "laps", 0.25 }, { "duration", 2 }, { "easeIn", 0.5 }, { "easeOut", 0.5 }, { "focal", 10 }, { "focal2", 10 } },
    dronie = { { "dist2", 10 }, { "height2", 5 }, { "duration", 2 }, { "easeIn", 0.5 }, { "easeOut", 0.5 }, { "focal", 10 }, { "focal2", 10 } },
    rocket = { { "height2", 10 }, { "duration", 2 }, { "easeIn", 0.5 }, { "easeOut", 0.5 }, { "focal", 10 }, { "focal2", 10 } },
    helix = { { "radius2", 5 }, { "height2", 5 }, { "laps", 0.25 }, { "duration", 2 }, { "easeIn", 0.5 }, { "easeOut", 0.5 }, { "focal", 10 }, { "focal2", 10 } },
    approach = { { "dist", 10 }, { "height", 5 }, { "dist2", 1 }, { "duration", 2 }, { "easeIn", 0.5 }, { "easeOut", 0.5 }, { "focal", 10 }, { "focal2", 10 } },
    follow = { { "dist", 2 }, { "height", 1 }, { "relAngle", math.rad(15) }, { "relAngle2", math.rad(15) }, { "lag", 0.25 }, { "side", 2 },
        { "duration", 5 }, { "focal", 10 }, { "focal2", 10 } },
    spotlight = {},
    static = { { "duration", 5 }, { "focal", 10 }, { "focal2", 10 } },
    boomerang = { { "radius2", 5 }, { "height2", 2 }, { "duration", 2 }, { "easeIn", 0.5 }, { "easeOut", 0.5 }, { "focal", 10 }, { "focal2", 10 } },
    pass = { { "side", 1 }, { "height", 0.2 }, { "passAt", 0.5 }, { "duration", 2 }, { "focal", 10 }, { "focal2", 10 } },
    parallel = { { "dist", 2 }, { "height", 0.5 }, { "angle0", math.rad(15) }, { "duration", 2 }, { "focal", 10 }, { "focal2", 10 } },
    topdown = { { "height", 5 }, { "height2", 5 }, { "duration", 2 }, { "easeIn", 0.5 }, { "easeOut", 0.5 }, { "focal", 10 }, { "focal2", 10 } },
    mount = { { "duration", 2 }, { "focal", 10 }, { "focal2", 10 } },
    pov = { { "duration", 2 }, { "focal", 10 }, { "focal2", 10 } },
    pair = { { "margin", 1 }, { "elev", math.rad(5) }, { "duration", 2 }, { "focal", 10 }, { "focal2", 10 } },
}

-- Pohled postavy: oči nad zemí, kam se dívá (m před ní, o kolik níž), přes rameno: za ní, do strany, výška.
Mo.EYE_HEIGHT = 1.62
Mo.EYE_FORWARD = 0.2
Mo.SHOULDER_BACK = 0.9
Mo.SHOULDER_SIDE = 0.45
Mo.SHOULDER_HEIGHT = 1.75
Mo.POV_VARIANTS = { "eyes", "shoulderL", "shoulderR" }
-- Dva cíle: poměr stran obrazu, pro který se vzdálenost počítá (šířka záběru).
Mo.ASPECT = 16 / 9
-- Nejmenší výška kamery nad terénem v režimu (jinak 0,5 m); průjezd jde nízko k zemi.
Mo.CLEARANCE = { pass = 0.1 }
-- Režimy, ve kterých je výška kamery nad terénem v místě kamery (ne nad cílem).
Mo.GROUND_HEIGHT = { pass = true }

Mo.LOOK_HEIGHT = 1.5

-- Posun kamery bloku vůči tomu, co dělá režim (K v bloku): shift = metry vpravo, nahoru a dopředu v osách kamery režimu,
-- aim = přidaný yaw a pitch. Kamera se tak posune a natočí stejně po celý blok.
function Mo.applyShift(track, x, y, z, q)
    if track.shiftX == nil and track.aimYaw == nil then
        return x, y, z, q
    end
    local yaw, pitch, roll = M.quatToYawPitchRoll(q)
    local rx, ry, rz = M.rightFromYaw(yaw)
    local ux, uy, uz = M.upFromYawPitch(yaw, pitch)
    local fx, fy, fz = M.forwardFromYawPitch(yaw, pitch)
    local sx, sy, sz = track.shiftX or 0, track.shiftY or 0, track.shiftZ or 0
    x = x + rx * sx + ux * sy + fx * sz
    y = y + ry * sx + uy * sy + fy * sz
    z = z + rz * sx + uz * sy + fz * sz
    return x, y, z, M.quatFromYawPitchRoll(yaw + (track.aimYaw or 0), pitch + (track.aimPitch or 0), roll)
end

-- Posun a natočení, se kterými póza režimu (x, y, z, q) skončí v póze kamery (cx…, cyaw, cpitch).
function Mo.shiftFromCamera(track, x, y, z, q, cx, cy, cz, cyaw, cpitch)
    local yaw, pitch = M.quatToYawPitchRoll(q)
    local rx, ry, rz = M.rightFromYaw(yaw)
    local ux, uy, uz = M.upFromYawPitch(yaw, pitch)
    local fx, fy, fz = M.forwardFromYawPitch(yaw, pitch)
    local dx, dy, dz = cx - x, cy - y, cz - z
    track.shiftX = dx * rx + dy * ry + dz * rz
    track.shiftY = dx * ux + dy * uy + dz * uz
    track.shiftZ = dx * fx + dy * fy + dz * fz
    track.aimYaw = M.angleDiff(yaw, cyaw)
    track.aimPitch = cpitch - pitch
end

function Mo.clearShift(track)
    track.shiftX, track.shiftY, track.shiftZ, track.aimYaw, track.aimPitch = nil, nil, nil, nil, nil
end

-- Režimy, v nichž kamera stojí na pevném místě (track.camX / camY / camZ) a drží natočení. Sledování z bodu má místo
-- stanoviště K-framy s polohou (S.KEYED), natáčení za cílem dodá režim.
Mo.STANDS = { static = true }

-- Statická kamera: stojí na místě a drží natočení, nepotřebuje žádný cíl.
function Mo.initStatic(x, y, z, yaw, pitch)
    return { mode = "static", camX = x, camY = y, camZ = z, yaw = yaw, pitch = pitch, duration = Mo.DEFAULTS.static.duration }
end

-- Sledování: úhel kamery vůči směru jízdy (0 = zezadu, kladný = z pravé strany vozidla, pí = zepředu).
Mo.FOLLOW_ORDER = { "behind", "left", "right", "front", "camera" }
Mo.FOLLOW_ANGLES = { behind = 0, left = -math.pi / 2, right = math.pi / 2, front = math.pi }

-- Parametry uložené v radiánech se uživateli ukazují ve stupních.
Mo.DISPLAY_SCALE = { relAngle = 180 / math.pi, relAngle2 = 180 / math.pi, angle0 = 180 / math.pi, elev = 180 / math.pi }

-- Pojmenovaná strana sledování podle úhlu, nebo nil, když je úhel vlastní.
function Mo.followSide(track)
    local a = track.relAngle or 0
    for _, side in ipairs(Mo.FOLLOW_ORDER) do
        local preset = Mo.FOLLOW_ANGLES[side]
        if preset ~= nil and math.abs(M.angleDiff(preset, a)) < 0.01 then
            return side
        end
    end
    return nil
end

-- Nový režim podle současné kamery (cx, cy, cz) a objektu (tx, ty, tz).
function Mo.init(mode, target, cx, cy, cz, tx, ty, tz, heading, side)
    local track = { mode = mode, target = target, lookHeight = Mo.LOOK_HEIGHT }
    for k, v in pairs(Mo.DEFAULTS[mode]) do
        track[k] = v
    end
    local dx, dz = cx - tx, cz - tz
    local horizontal = math.sqrt(dx * dx + dz * dz)
    track.angle0 = horizontal > 0.5 and math.atan2(dx, dz) or 0
    local height = cy - ty
    if mode == "orbit" then
        track.radius = M.clamp(horizontal, 4, 120)
        track.height = M.clamp(height, 1, 80)
    elseif mode == "dronie" then
        track.dist = M.clamp(horizontal, 2, 60)
        track.height = M.clamp(height, 0.5, 40)
        track.dist2 = math.max(track.dist2, track.dist + 20)
    elseif mode == "helix" then
        track.radius = M.clamp(horizontal, 3, 60)
        track.height = M.clamp(height, 1, 40)
        track.radius2 = math.max(track.radius2, track.radius + 15)
    elseif mode == "approach" then
        track.dist = math.max(M.clamp(horizontal, 20, 200), track.dist2 + 10)
        track.height = M.clamp(height, 2, 80)
    elseif mode == "boomerang" then
        track.radius = M.clamp(horizontal, 4, 60)
        track.height = M.clamp(height, 1, 30)
        track.radius2 = math.max(track.radius2, track.radius * 2)
    elseif mode == "spotlight" then
        track.camX, track.camY, track.camZ = cx, cy, cz
        track.dist0 = math.max(math.sqrt(dx * dx + dz * dz + height * height), 1)
    elseif mode == "pass" then
        -- strana cesty, na které je kamera; vzdálenost od ní, je-li kamera blízko
        local h = heading or 0
        local across = -dx * math.cos(h) + dz * math.sin(h)
        if horizontal > 2 and horizontal < 40 then
            track.side = M.clamp(math.abs(across), 2, 30)
        end
        track.side = across < 0 and -track.side or track.side
        track.passAt = track.duration * 0.5
    elseif mode == "parallel" then
        if horizontal > 3 then
            track.dist = M.clamp(horizontal, 4, 60)
            track.height = M.clamp(height, 0.5, 40)
        else
            local rx, _, rz = M.rightFromYaw(heading or 0)
            track.angle0 = math.atan2(rx, rz)
        end
    elseif mode == "topdown" then
        if height > 8 then
            track.height = M.clamp(height, 8, 150)
            track.height2 = track.height
        end
    elseif mode == "pair" then
        track.elev = M.clamp(math.atan2(height, math.max(horizontal, 0.1)), 0.15, 1.2)
    elseif mode == "follow" and side ~= nil then
        local rel = Mo.FOLLOW_ANGLES[side]
        if rel == nil then
            -- strana, na které je právě kamera, vůči směru jízdy
            local h = heading or 0
            local along = dx * math.sin(h) + dz * math.cos(h)
            local across = -dx * math.cos(h) + dz * math.sin(h)
            rel = math.atan2(across, -along)
            track.dist = M.clamp(horizontal, 3, 60)
            track.height = M.clamp(height, 1, 40)
        end
        track.relAngle = rel
        track.lead = 6 * math.cos(rel)
    end
    return track
end

-- Délky rozjezdu a dojezdu (s) a délka režimu; dohromady nejvýš celá délka.
function Mo.easeTimes(track)
    local d = math.max(track.duration or 1, 0.1)
    local base = track.ease or (Mo.DEFAULTS[track.mode] or {}).ease or 0
    local a1 = math.max(track.easeIn or base, 0)
    local a2 = math.max(track.easeOut or base, 0)
    local sum = a1 + a2
    if sum > d then
        a1, a2 = a1 * d / sum, a2 * d / sum
    end
    return a1, a2, d
end

-- Průběh pohybu 0..1 v čase t: rozjezd, rovnoměrná část, dojezd. Rychlost nabíhá a mizí plynule, takže kamera
-- nezačíná ani nekončí skokem; celková dráha je vždy 1.
local function baseProgress(track, t)
    local a1, a2, d = Mo.easeTimes(track)
    t = M.clamp(t, 0, d)
    local v = 1 / (d - (a1 + a2) * 0.5)
    if a1 > 1e-6 and t < a1 then
        return v * t * t / (2 * a1)
    end
    if a2 > 1e-6 and t > d - a2 then
        local rest = d - t
        return 1 - v * rest * rest / (2 * a2)
    end
    return v * (a1 * 0.5 + (t - a1))
end

-- Rychlost pohybu v čase t jako podíl nejvyšší rychlosti 0..1 (pro kreslení profilu na ose).
local function rampFactor(track, t)
    local a1, a2, d = Mo.easeTimes(track)
    if a1 > 1e-6 and t < a1 then
        return M.clamp(t / a1, 0, 1)
    end
    if a2 > 1e-6 and t > d - a2 then
        return M.clamp((d - t) / a2, 0, 1)
    end
    return 1
end

---------------------------------------------------------------------------------------------------
-- keyframy uvnitř režimu: track.marks = { { u, focal, speed } } seřazené podle u (0..1 z délky úseku, takže se
-- při zrychlení nebo zpomalení bloku posunou spolu s ním). focal = ohnisko v mm v tom bodě, speed = násobek rychlosti
-- pohybu po dráze režimu (1 = beze změny). Mezi začátkem (focal, rychlost 1), keyframy a koncem (focal2, rychlost 1)
-- se hodnoty plynule mění.

Mo.MARK_MIN_SECONDS = 0.3
Mo.SPEED_MIN, Mo.SPEED_MAX = 0.2, 5
Mo.MOVING = { orbit = true, dronie = true, rocket = true, helix = true, approach = true, boomerang = true }

local function hasMarks(track)
    return track.marks ~= nil and #track.marks > 0
end

-- Nejmenší odstup keyframů a od kraje úseku jako díl jeho délky.
function Mo.markGap(track)
    return math.min(Mo.MARK_MIN_SECONDS / math.max(track.duration or 1, 0.1), 0.2)
end

function Mo.speedMultiplier(track, t)
    if not hasMarks(track) then
        return 1
    end
    local u = M.clamp(t / math.max(track.duration or 1, 0.1), 0, 1)
    local u0, v0 = 0, 1
    for _, m in ipairs(track.marks) do
        if u <= m.u then
            local span = m.u - u0
            if span <= 1e-9 then
                return m.speed or 1
            end
            return v0 + ((m.speed or 1) - v0) * (u - u0) / span
        end
        u0, v0 = m.u, m.speed or 1
    end
    local span = 1 - u0
    if span <= 1e-9 then
        return 1
    end
    return v0 + (1 - v0) * (u - u0) / span
end

-- Okamžitá rychlost pohybu po dráze: rozjezd a dojezd krát násobek z keyframů.
local function rate(track, t)
    return rampFactor(track, t) * Mo.speedMultiplier(track, t)
end

local PROGRESS_STEPS = 200

local function integral(track, upTo)
    if upTo <= 0 then
        return 0
    end
    local h = upTo / PROGRESS_STEPS
    local sum = 0
    for i = 0, PROGRESS_STEPS - 1 do
        sum = sum + rate(track, (i + 0.5) * h)
    end
    return sum * h
end

function Mo.progress(track, t)
    if not Mo.MOVING[track.mode] or not hasMarks(track) then
        return baseProgress(track, t)
    end
    local d = math.max(track.duration or 1, 0.1)
    local total = integral(track, d)
    if total <= 1e-9 then
        return M.clamp(t / d, 0, 1)
    end
    return M.clamp(integral(track, M.clamp(t, 0, d)) / total, 0, 1)
end

-- Rychlost pohybu v čase t jako podíl nejvyšší rychlosti 0..1 (pro kreslení profilu na ose).
function Mo.speedFactor(track, t)
    if not Mo.MOVING[track.mode] or not hasMarks(track) then
        return rampFactor(track, t)
    end
    local d = math.max(track.duration or 1, 0.1)
    local peak = 1e-9
    for i = 0, 48 do
        peak = math.max(peak, rate(track, d * i / 48))
    end
    return M.clamp(rate(track, t) / peak, 0, 1)
end

-- Ohnisko v keyframu: zadané, jinak podle hodnoty v tomto bodě bez keyframu.
local function mixFocal(f1, f2, u)
    return f1 * (f2 / f1) ^ M.smoothstep(M.clamp(u, 0, 1))
end

-- Přidá keyframe v dílu u délky úseku s hodnotami, které tam režim právě má (tvar záběru se tím nezmění).
-- Vrací index; když je v dosahu odstupu jiný keyframe, vrací jeho index a nic nepřidává.
function Mo.addMark(track, u, fallbackFocal)
    local gap = Mo.markGap(track)
    u = M.clamp(u, gap, 1 - gap)
    track.marks = track.marks or {}
    for i, m in ipairs(track.marks) do
        if math.abs(m.u - u) < gap then
            return i, false
        end
    end
    local d = math.max(track.duration or 1, 0.1)
    local mark = { u = u, focal = Mo.focalAt(track, u * d, nil, fallbackFocal), speed = Mo.speedMultiplier(track, u * d) }
    local index = #track.marks + 1
    for i, m in ipairs(track.marks) do
        if m.u > u then
            index = i
            break
        end
    end
    table.insert(track.marks, index, mark)
    return index, true
end

function Mo.removeMark(track, index)
    if track.marks ~= nil and track.marks[index] ~= nil then
        table.remove(track.marks, index)
        if #track.marks == 0 then
            track.marks = nil
        end
    end
end

-- Posune keyframe na díl u délky úseku; nepředběhne sousedy ani kraje. Vrací skutečné u.
function Mo.moveMark(track, index, u)
    local marks = track.marks
    local mark = marks ~= nil and marks[index] or nil
    if mark == nil then
        return nil
    end
    local gap = Mo.markGap(track)
    local lo = index > 1 and marks[index - 1].u + gap or gap
    local hi = index < #marks and marks[index + 1].u - gap or 1 - gap
    mark.u = M.clamp(u, lo, math.max(lo, hi))
    return mark.u
end

-- Změna keyframu o steps kroků: key = "focal" (ohnisko) nebo "speed" (násobek rychlosti, krok ×1,25).
function Mo.adjustMark(track, index, key, steps)
    local mark = track.marks ~= nil and track.marks[index] or nil
    if mark == nil then
        return false
    end
    if key == "focal" then
        mark.focal = M.stepFocal(mark.focal, steps, 1.15)
    else
        mark.speed = M.clamp((mark.speed or 1) * 1.25 ^ steps, Mo.SPEED_MIN, Mo.SPEED_MAX)
    end
    return true
end

-- Hodnota parametru tak, jak se ukazuje v menu (rozjezd a dojezd i z výchozí hodnoty).
function Mo.value(track, key)
    if key == "focal" then
        return track.focal or 35
    end
    if key == "focal2" then
        return track.focal2 or track.focal or 35
    end
    if key == "easeIn" or key == "easeOut" then
        local a1, a2 = Mo.easeTimes(track)
        return key == "easeIn" and a1 or a2
    end
    if key == "relAngle2" then
        return track.relAngle2 or track.relAngle or 0
    end
    if key == "lag" then
        return track.lag or 0
    end
    return track[key]
end

local function ring(tx, tz, angle, radius)
    return tx + math.sin(angle) * radius, tz + math.cos(angle) * radius
end

-- Kamera v čase t: px, py, pz, lx, ly, lz (bod, kam hledí) a u pohledu shora i natočení q (kam hledí pak neplatí).
-- target = {x, y, z, heading}; extra.pass = cíl v okamžiku průjezdu, extra.second = druhý cíl.
function Mo.evaluate(track, t, target, extra)
    local d = math.max(track.duration or 1, 0.1)
    local u = M.clamp(t / d, 0, 1)
    local e = Mo.progress(track, t)
    local tx, ty, tz = target.x, target.y, target.z
    local lx, ly, lz = tx, ty + (track.lookHeight or Mo.LOOK_HEIGHT), tz
    local mode = track.mode
    local angle0 = track.angle0 or 0
    local px, py, pz
    if mode == "orbit" then
        local angle = angle0 + (track.dir or 1) * 2 * math.pi * (track.laps or 1) * e
        px, pz = ring(tx, tz, angle, track.radius)
        py = ty + track.height
    elseif mode == "dronie" then
        local dist = track.dist + (track.dist2 - track.dist) * e
        px, pz = ring(tx, tz, angle0, dist)
        py = ty + track.height + (track.height2 - track.height) * e
    elseif mode == "rocket" then
        px, pz = ring(tx, tz, angle0, track.radius or 1.5)
        py = ty + track.height + (track.height2 - track.height) * e
        ly = ty
    elseif mode == "helix" then
        local angle = angle0 + (track.dir or 1) * 2 * math.pi * (track.laps or 1) * e
        px, pz = ring(tx, tz, angle, track.radius + (track.radius2 - track.radius) * e)
        py = ty + track.height + (track.height2 - track.height) * e
    elseif mode == "approach" then
        local dist = track.dist + (track.dist2 - track.dist) * e
        px, pz = ring(tx, tz, angle0, dist)
        py = ty + track.height + (track.height2 - track.height) * e
    elseif mode == "follow" then
        local heading = target.heading or 0
        local fx, fz = math.sin(heading), math.cos(heading)
        local rx, _, rz = M.rightFromYaw(heading)
        local rel = track.relAngle or 0
        if track.relAngle2 ~= nil then
            -- přechod úhlu během bloku (zezadu na bok…) nejkratší cestou
            rel = rel + M.angleDiff(rel, track.relAngle2) * e
        end
        local ca, sa = math.cos(rel), math.sin(rel)
        px = tx + (-fx * ca + rx * sa) * track.dist + rx * (track.side or 0)
        pz = tz + (-fz * ca + rz * sa) * track.dist + rz * (track.side or 0)
        py = ty + track.height
        lx, lz = tx + fx * (track.lead or 0), tz + fz * (track.lead or 0)
    elseif mode == "spotlight" then
        px, py, pz = track.camX, track.camY, track.camZ
    elseif mode == "pass" then
        -- stanoviště vedle místa, kde cíl bude v čase průjezdu; výšku nad zemí v něm doplní editor
        local at = extra ~= nil and extra.pass or target
        local rx, _, rz = M.rightFromYaw(at.heading or 0)
        px, pz = at.x + rx * track.side, at.z + rz * track.side
        py = at.y + track.height
    elseif mode == "parallel" then
        px, pz = ring(tx, tz, angle0, track.dist)
        py = ty + track.height
    elseif mode == "topdown" then
        local yaw = track.rotate and (target.heading or 0) or math.pi
        px, pz = tx, tz
        py = ty + track.height + ((track.height2 or track.height) - track.height) * e
        return px, py, pz, tx, ty, tz, M.quatFromYawPitchRoll(yaw, math.pi * 0.5 - 1e-3, 0)
    elseif mode == "pair" then
        local second = extra ~= nil and extra.second or target
        local mx, my, mz = (tx + second.x) * 0.5, (ty + second.y) * 0.5, (tz + second.z) * 0.5
        local dx, dz = second.x - tx, second.z - tz
        local sep = math.sqrt(dx * dx + dz * dz)
        -- kolmo na spojnici, na té straně, kam ukazuje angle0 (bez přeskoku, když se cíle prohodí)
        local nx, nz = math.sin(angle0), math.cos(angle0)
        if sep > 0.5 then
            local px1, pz1 = dz / sep, -dx / sep
            if px1 * nx + pz1 * nz < 0 then
                px1, pz1 = -px1, -pz1
            end
            nx, nz = px1, pz1
        end
        local vfov = M.focalToFov(Mo.focalAt(track, t))
        local hfov = 2 * math.atan(math.tan(vfov * 0.5) * Mo.ASPECT)
        local dist = math.max((sep * 0.5 + track.margin) / math.tan(hfov * 0.5), 4)
        local elev = track.elev or 0.45
        px, pz = mx + nx * dist * math.cos(elev), mz + nz * dist * math.cos(elev)
        py = my + dist * math.sin(elev)
        lx, ly, lz = mx, my + (track.lookHeight or Mo.LOOK_HEIGHT), mz
    elseif mode == "static" then
        px, py, pz = track.camX, track.camY, track.camZ
        local fx, fy, fz = M.forwardFromYawPitch(track.yaw or 0, track.pitch or 0)
        lx, ly, lz = px + fx * 20, py + fy * 20, pz + fz * 20
    elseif mode == "boomerang" then
        -- ovál: blízko u startu, nejdál a nejvýš v půlce kola, zpět na start
        local phase = 2 * math.pi * e
        local angle = angle0 + (track.dir or 1) * phase
        local wide = (1 - math.cos(phase)) * 0.5
        px, pz = ring(tx, tz, angle, track.radius + (track.radius2 - track.radius) * wide)
        py = ty + track.height + (track.height2 - track.height) * wide
    else
        return nil
    end
    return px, py, pz, lx, ly, lz
end

function Mo.adjust(track, key, steps)
    local step
    for _, a in ipairs(Mo.ADJUSTABLE[track.mode] or {}) do
        if a[1] == key then
            step = a[2]
        end
    end
    if step == nil or Mo.value(track, key) == nil then
        return false
    end
    local value = Mo.value(track, key) + step * steps
    if key == "easeIn" or key == "easeOut" then
        local a1, a2, d = Mo.easeTimes(track)
        local other = key == "easeIn" and a2 or a1
        track.easeIn, track.easeOut = a1, a2
        track[key] = M.clamp(value, 0, math.max(d - other, 0))
        return true
    end
    if key == "relAngle" or key == "relAngle2" or key == "angle0" then
        if key == "relAngle2" and track.relAngle2 == nil then
            value = (track.relAngle or 0) + step * steps
        end
        track[key] = M.angleDiff(0, value)
        return true
    end
    if key == "elev" then
        track[key] = M.clamp(value, 0.1, 1.4)
        return true
    end
    if key == "passAt" then
        track[key] = M.clamp(value, 0, track.duration or 0)
        return true
    end
    if key == "lag" then
        track[key] = M.clamp(value, 0, 4)
        return true
    end
    if key == "height" and track.mode == "pass" then
        track[key] = math.max(value, 0.1)
        return true
    end
    if key == "focal" or key == "focal2" then
        track[key] = M.stepFocal(Mo.value(track, key), steps * 5)
        return true
    end
    local minimum = (key == "side") and -60 or (key == "laps" and 0.25 or (key == "duration" and 2 or 0.5))
    track[key] = math.max(minimum, value)
    if key == "duration" and track.passAt ~= nil then
        track.passAt = math.min(track.passAt, track[key])
    end
    return true
end

-- Úsek [from, to] (s od začátku) bloku jako nová stopa stejného režimu: ohnisko na krajích podle původního průběhu, značky
-- uvnitř úseku se přepočtou na jeho délku. Bez stálých čísel (uid).
function Mo.piece(track, from, to)
    local d = math.max(track.duration or 1, 0.1)
    local piece = CinemaShot.copyTable(track)
    piece.uid = nil
    piece.duration = to - from
    if not track.autoZoom then
        piece.focal = Mo.focalAt(track, from)
        piece.focal2 = Mo.focalAt(track, to)
    end
    piece.marks = nil
    for _, m in ipairs(track.marks or {}) do
        local at = m.u * d
        if at > from + 1e-6 and at < to - 1e-6 then
            local c = CinemaShot.copyTable(m)
            c.uid = nil
            c.u = (at - from) / (to - from)
            piece.marks = piece.marks or {}
            piece.marks[#piece.marks + 1] = c
        end
    end
    return piece
end

---------------------------------------------------------------------------------------------------
-- připevnění na vozidlo a pohled postavy (čistá matematika; uzly a stav postavy dodá editor)

local function dot(ax, ay, az, b)
    return ax * b[1] + ay * b[2] + az * b[3]
end

-- Kamera v poloze (cx, cy, cz) s natočením yaw, pitch připevněná k rámu frame = { x, y, z, ax, ay, az } (osy uzlu
-- ve světě): poloha a směr pohledu i horní strana v souřadnicích uzlu.
function Mo.mountFromCamera(track, frame, cx, cy, cz, yaw, pitch)
    local dx, dy, dz = cx - frame.x, cy - frame.y, cz - frame.z
    local fx, fy, fz = M.forwardFromYawPitch(yaw, pitch)
    local ux, uy, uz = M.upFromYawPitch(yaw, pitch)
    track.ox, track.oy, track.oz = dot(dx, dy, dz, frame.ax), dot(dx, dy, dz, frame.ay), dot(dx, dy, dz, frame.az)
    track.fx, track.fy, track.fz = dot(fx, fy, fz, frame.ax), dot(fx, fy, fz, frame.ay), dot(fx, fy, fz, frame.az)
    track.ux, track.uy, track.uz = dot(ux, uy, uz, frame.ax), dot(ux, uy, uz, frame.ay), dot(ux, uy, uz, frame.az)
    return track
end

local function toWorld(frame, x, y, z)
    return frame.ax[1] * x + frame.ay[1] * y + frame.az[1] * z,
        frame.ax[2] * x + frame.ay[2] * y + frame.az[2] * z,
        frame.ax[3] * x + frame.ay[3] * y + frame.az[3] * z
end

-- Připevněná kamera ve světě: x, y, z, q. Bez uložené polohy je kamera v počátku uzlu a hledí po jeho -Z (kamera vozidla).
function Mo.mountPose(track, frame)
    local ox, oy, oz = toWorld(frame, track.ox or 0, track.oy or 0, track.oz or 0)
    local fx, fy, fz = toWorld(frame, track.fx or 0, track.fy or 0, track.fz or -1)
    local ux, uy, uz = toWorld(frame, track.ux or 0, track.uy or 1, track.uz or 0)
    return frame.x + ox, frame.y + oy, frame.z + oz, M.quatFromForwardUp(fx, fy, fz, ux, uy, uz)
end

-- Pohled postavy v čase t (s od začátku záběru): st = { x, y, z, heading } postavy, kmh = rychlost chůze. Oči se do kroku
-- jemně pohupují; přes rameno je kamera za postavou a hledí kus před ni. x, y, z, q.
function Mo.povPose(track, st, t, kmh)
    local h = st.heading or 0
    local fx, fz = math.sin(h), math.cos(h)
    local rx, _, rz = M.rightFromYaw(h)
    local variant = track.variant or "eyes"
    if variant == "eyes" then
        local walk = M.clamp((kmh or 0) / 5, 0, 1.8)
        local phase = 2 * math.pi * t * (0.9 + (kmh or 0) * 0.12)
        local bob = 0.025 * walk * math.sin(phase)
        local x, y, z = st.x + fx * Mo.EYE_FORWARD, st.y + Mo.EYE_HEIGHT + bob, st.z + fz * Mo.EYE_FORWARD
        local pitch = 0.08
        return x, y, z, M.quatFromYawPitchRoll(h, pitch, 0.012 * walk * math.sin(phase * 0.5))
    end
    local side = variant == "shoulderL" and -1 or 1
    local x = st.x - fx * Mo.SHOULDER_BACK + rx * Mo.SHOULDER_SIDE * side
    local z = st.z - fz * Mo.SHOULDER_BACK + rz * Mo.SHOULDER_SIDE * side
    local y = st.y + Mo.SHOULDER_HEIGHT
    local yaw, pitch = M.yawPitchFromDirection(st.x + fx * 8 - x, st.y + 1.4 - y, st.z + fz * 8 - z)
    return x, y, z, M.quatFromYawPitchRoll(yaw, pitch, 0)
end

-- Ohnisko (mm) režimu v čase t od jeho začátku: plynulý zoom z focal na focal2, u sledování z bodu i automatické držení
-- velikosti vozidla podle vzdálenosti; jinak stálé.
function Mo.focalAt(track, t, distance, fallback)
    local focal = track.focal or fallback or 35
    if track.autoZoom and distance ~= nil and track.dist0 ~= nil then
        return M.clamp(focal * distance / track.dist0, M.FOCAL_MIN, M.FOCAL_MAX)
    end
    local u = M.clamp(t / math.max(track.duration or 1, 0.1), 0, 1)
    local last = track.focal2 or focal
    if hasMarks(track) then
        local u0, f0 = 0, focal
        for _, m in ipairs(track.marks) do
            local f1 = m.focal or f0
            if u <= m.u then
                return mixFocal(f0, f1, (u - u0) / math.max(m.u - u0, 1e-9))
            end
            u0, f0 = m.u, f1
        end
        return mixFocal(f0, last, (u - u0) / math.max(1 - u0, 1e-9))
    end
    if last ~= focal then
        return mixFocal(focal, last, u)
    end
    return focal
end
