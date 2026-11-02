-- Nahrávání ruční jízdy: vzorky polohy, rychlosti, os a stavů vozidla se zjednoduší na trasu (body s příznakem couvání),
-- křivku rychlosti, křivky os a akce herce, takže jízda jde v editoru dál upravovat. Bez herních API.
-- Čas křivek a akcí je od začátku nahrávky, tedy od startu jízdy herce; křivka rychlosti drží časování, aby osy a akce seděly.

CinemaRecording = CinemaRecording or {}
local Rc = CinemaRecording
local Ch = CinemaChannels
local A = CinemaActions
local M = CinemaMath
local R = CinemaRoute

Rc.SAMPLE_DT = 0.2 -- s; odstup vzorků
Rc.PATH_TOL = 0.3 -- m; o kolik se zjednodušená trasa smí odchýlit od jízdy (víc = přehrání vedle stopy, třeba do zdi)
Rc.SPEED_TOL = 0.6 -- km/h
Rc.AXIS_TOL = 0.01 -- díl rozsahu osy
Rc.MIN_POINT_GAP = 1.5 -- m; nejmenší odstup naklikaných bodů
Rc.MOVING_KMH = 1.5 -- pod touto rychlostí se směr jízdy nemění
Rc.MIN_DISTANCE = 3 -- m; kratší jízda se neuloží

-- axes = { { id, min, max }, … }: osy vozidla, jejichž hodnoty se při vzorkování předávají v axisValues[id].
function Rc.new(axes)
    return { samples = {}, axes = axes or {} }
end

-- Vzorek v čase t (s od začátku): poloha, rychlost (km/h), směr jízdy (>0 vpřed, <0 couvá), hodnoty os a stavy vozidla
-- jako { ["lights:0"] = 1, … } (druh a číslo článku soupravy, 0 = celá souprava).
function Rc.add(rec, t, x, z, kmh, direction, axisValues, states)
    rec.samples[#rec.samples + 1] = { t = t, x = x, z = z, kmh = math.abs(kmh or 0), dir = direction or 1, axes = axisValues, states = states }
end

-- Couvá se ve vzorku? Směr se změní, až když ho potvrdí dva vzorky za sebou (šum při rozjezdu a zastavení se ignoruje).
local function reverseFlags(samples)
    local flags, current, pending, count = {}, false, nil, 0
    for i, s in ipairs(samples) do
        if s.kmh >= Rc.MOVING_KMH then
            local want = s.dir < 0
            if want ~= current then
                if pending == want then
                    count = count + 1
                else
                    pending, count = want, 1
                end
                if count >= 2 then
                    current, pending, count = want, nil, 0
                end
            else
                pending, count = nil, 0
            end
        end
        flags[i] = current
    end
    return flags
end

-- Ramer-Douglas-Peucker nad polohou vzorků first..last; vrací seřazené indexy zachovaných vzorků.
local function simplifyPath(samples, first, last, tol)
    local keep = { [first] = true, [last] = true }
    local stack = { { first, last } }
    while #stack > 0 do
        local range = table.remove(stack)
        local a, b = samples[range[1]], samples[range[2]]
        local dx, dz = b.x - a.x, b.z - a.z
        local len = math.sqrt(dx * dx + dz * dz)
        local worst, worstIndex = -1, nil
        for i = range[1] + 1, range[2] - 1 do
            local s = samples[i]
            local d
            if len < 1e-6 then
                d = math.sqrt((s.x - a.x) ^ 2 + (s.z - a.z) ^ 2)
            else
                d = math.abs((s.x - a.x) * dz - (s.z - a.z) * dx) / len
            end
            if d > worst then
                worst, worstIndex = d, i
            end
        end
        if worstIndex ~= nil and worst > tol then
            keep[worstIndex] = true
            stack[#stack + 1] = { range[1], worstIndex }
            stack[#stack + 1] = { worstIndex, range[2] }
        end
    end
    local list = {}
    for i = first, last do
        if keep[i] then
            list[#list + 1] = i
        end
    end
    return list
end

local function buildPoints(samples)
    local flags = reverseFlags(samples)
    local runs = {}
    local from = 1
    for i = 2, #samples + 1 do
        if i == #samples + 1 or flags[i] ~= flags[i - 1] then
            runs[#runs + 1] = { from = from, to = i - 1, reverse = flags[i - 1] }
            from = i - 1
        end
    end
    local points = {}
    for r, run in ipairs(runs) do
        local kept = simplifyPath(samples, run.from, run.to, Rc.PATH_TOL)
        for k, index in ipairs(kept) do
            local s = samples[index]
            local last = points[#points]
            local isEnd = k == #kept
            local skip = (r > 1 and k == 1) -- bod změny směru patří předchozímu úseku
            if not skip and last ~= nil and not isEnd and math.sqrt((s.x - last[1]) ^ 2 + (s.z - last[2]) ^ 2) < Rc.MIN_POINT_GAP then
                skip = true
            end
            if not skip then
                points[#points + 1] = { s.x, s.z, nil, nil, run.reverse or nil }
            end
        end
    end
    return points
end

local function channelFrom(samples, tol)
    local list = Ch.simplify(samples, tol)
    local ch = Ch.new()
    for _, p in ipairs(list) do
        ch.points[#ch.points + 1] = { t = p.t, v = p.v, mode = "linear" }
    end
    return ch
end

local function buildActions(samples, t0)
    local seen, keys = {}, {}
    for _, s in ipairs(samples) do
        for key in pairs(s.states or {}) do
            if not seen[key] then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
    end
    table.sort(keys)
    local actions = {}
    for _, key in ipairs(keys) do
        local kind, entry = key:match("^(%w+):(%d+)$")
        local open, previous = nil, 0
        for _, s in ipairs(samples) do
            local value = s.states ~= nil and s.states[key] or previous
            if value ~= previous then
                local t = s.t - t0
                if open ~= nil then
                    A.setDuration(open, t - open.t)
                    open = nil
                end
                if value ~= 0 then
                    open = { t = t, kind = kind, value = value, entry = tonumber(entry) }
                    actions[#actions + 1] = open
                end
                previous = value
            end
        end
    end
    for i, action in ipairs(actions) do
        action.order = i
    end
    table.sort(actions, function(a, b)
        if a.t ~= b.t then
            return a.t < b.t
        end
        return a.order < b.order
    end)
    for _, action in ipairs(actions) do
        action.order = nil
    end
    return actions
end

-- Hotová nahrávka: { points, curves, actions, duration, distance }; nil, když vozidlo skoro nejelo.
function Rc.finish(rec)
    local samples = rec.samples
    if #samples < 2 then
        return nil
    end
    local distance = 0
    for i = 2, #samples do
        distance = distance + math.sqrt((samples[i].x - samples[i - 1].x) ^ 2 + (samples[i].z - samples[i - 1].z) ^ 2)
    end
    if distance < Rc.MIN_DISTANCE then
        return nil
    end
    local t0 = samples[1].t
    local points = buildPoints(samples)
    if #points < 2 then
        return nil
    end
    local curves = {}
    local speed = {}
    for i, s in ipairs(samples) do
        speed[i] = { t = s.t - t0, v = s.kmh }
    end
    curves.speed = channelFrom(speed, Rc.SPEED_TOL)
    for _, axis in ipairs(rec.axes) do
        local values, low, high = {}, math.huge, -math.huge
        for _, s in ipairs(samples) do
            local v = s.axes ~= nil and s.axes[axis.id] or nil
            if v ~= nil then
                values[#values + 1] = { t = s.t - t0, v = v }
                low, high = math.min(low, v), math.max(high, v)
            end
        end
        local tol = (axis.max - axis.min) * Rc.AXIS_TOL
        if #values >= 2 and high - low > tol then
            curves[axis.id] = channelFrom(values, tol)
        end
    end
    return { points = points, curves = curves, actions = buildActions(samples, t0), duration = samples[#samples].t - t0,
        distance = distance }
end

---------------------------------------------------------------------------------------------------
-- Nahrávka chůze postavy: vzorky polohy a natočení se zjednoduší na body trasy s tempem (pomalu, chůze, běh), pauzami
-- s natočením a podlahou, skoky a zvednuté předměty na akce. Tempa postavy jsou stejná jako u hráče, ale jen tři (a bez
-- rozběhu), takže se časy akcí a křivek přepočítají podle místa na trase (v pauze podle času od zastavení), aby skok
-- i zvednutí přišly přesně na stejném místě.

Rc.PERSON_STOP_MPS = 0.5 -- m/s; pomaleji postava stojí
Rc.PERSON_MIN_STOP = 0.6 -- s; kratší zastavení je zaváhání, pauza z něj není
Rc.PERSON_SLOW_MPS = 2.5 -- m/s; pomaleji jde pomalu (postava i hráč: pomalu 1,5, chůze 4, běh 7 m/s)
Rc.PERSON_RUN_MPS = 5.5 -- m/s; rychleji běží
Rc.PERSON_MIN_GAIT = 1 -- s; kratší změna tempa se nepočítá
Rc.FLOOR_TOL = 0.3 -- m; stojí-li postava výš nad terénem, je na podlaze (bod dostane p[9])
Rc.CARRY_TOL = 0.02 -- m; tolerance křivek posunu neseného předmětu
Rc.CARRY_TURN_TOL = 2 -- °; tolerance křivek natočení

function Rc.newPerson()
    return { person = true, samples = {}, jumps = {}, carries = {} }
end

-- Vzorek chůze v čase t (s): poloha nohou, výška terénu pod nimi, natočení postavy a poloha neseného předmětu
-- held = { x, y, z, rx, ry, rz } (nil, když nic nenese).
function Rc.addStep(rec, t, x, y, z, ground, yaw, held)
    rec.samples[#rec.samples + 1] = { t = t, x = x, y = y, z = z, ground = ground, yaw = yaw, held = held }
end

function Rc.jump(rec, t)
    rec.jumps[#rec.jumps + 1] = t
end

-- Postava v čase t zvedla předmět: target jako u akce nesení (kde ležel, poloměr), yaw = jak přitom stála.
function Rc.pickUp(rec, t, target, yaw)
    rec.carries[#rec.carries + 1] = { t0 = t, target = target, yaw = yaw }
end

function Rc.drop(rec, t)
    local c = rec.carries[#rec.carries]
    if c ~= nil and c.t1 == nil then
        c.t1 = t
    end
end

local function gaitClass(mps)
    if mps < Rc.PERSON_STOP_MPS then
        return "stop"
    elseif mps < Rc.PERSON_SLOW_MPS then
        return "slow"
    elseif mps > Rc.PERSON_RUN_MPS then
        return "run"
    end
    return "walk"
end

-- Úseky stejného tempa nad intervaly vzorků (interval i = vzorek i - 1 → i): { cls, from, to } (indexy intervalů).
-- Krátké zastavení a krátká změna tempa se přidají k sousednímu úseku.
local function gaitRuns(samples)
    local runs = {}
    for i = 2, #samples do
        local a, b = samples[i - 1], samples[i]
        local dt = b.t - a.t
        local cls = gaitClass(dt > 1e-6 and math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2) / dt or 0)
        local last = runs[#runs]
        if last ~= nil and last.cls == cls then
            last.to = i
        else
            runs[#runs + 1] = { cls = cls, from = i, to = i }
        end
    end
    local function duration(r)
        return samples[r.to].t - samples[r.from - 1].t
    end
    local changed = true
    while changed do
        changed = false
        for k, r in ipairs(runs) do
            local short = duration(r) < (r.cls == "stop" and Rc.PERSON_MIN_STOP or Rc.PERSON_MIN_GAIT)
            local prev, nextRun = runs[k - 1], runs[k + 1]
            local into = nil
            if short and #runs > 1 then
                if r.cls == "stop" then
                    into = prev or nextRun
                else
                    into = (prev ~= nil and prev.cls ~= "stop" and prev) or (nextRun ~= nil and nextRun.cls ~= "stop" and nextRun) or nil
                end
            end
            if into ~= nil then
                into.from, into.to = math.min(into.from, r.from), math.max(into.to, r.to)
                table.remove(runs, k)
                changed = true
                break
            end
            if nextRun ~= nil and nextRun.cls == r.cls then
                r.to = nextRun.to
                table.remove(runs, k + 1)
                changed = true
                break
            end
        end
    end
    return runs
end

local function personPoint(s)
    local p = { s.x, s.z }
    if s.y ~= nil and s.ground ~= nil and s.y - s.ground > Rc.FLOOR_TOL then
        p[9] = s.y
    end
    return p
end

-- Body trasy postavy a pro každý bod vzorek příchodu a odchodu (u pauzy konec zastavení).
local function personPoints(samples, gaits)
    local points, arrive, leave = {}, {}, {}
    local function emit(index)
        points[#points + 1] = personPoint(samples[index])
        arrive[#points], leave[#points] = index, index
    end
    emit(1)
    for _, r in ipairs(gaitRuns(samples)) do
        local k = #points
        if r.cls == "stop" then
            local p, s = points[k], samples[r.to]
            p[4] = s.t - samples[r.from - 1].t
            p[6] = s.yaw
            leave[k] = r.to
        else
            if r.cls == "slow" or r.cls == "run" then
                points[k][3] = gaits[r.cls]
            end
            local kept = simplifyPath(samples, r.from - 1, r.to, Rc.PATH_TOL)
            for n = 2, #kept do
                local s, last = samples[kept[n]], points[#points]
                if n == #kept or math.sqrt((s.x - last[1]) ^ 2 + (s.z - last[2]) ^ 2) >= Rc.MIN_POINT_GAP then
                    emit(kept[n])
                    if n < #kept and (r.cls == "slow" or r.cls == "run") then
                        points[#points][3] = gaits[r.cls]
                    end
                end
            end
        end
    end
    return points, arrive, leave
end

-- Přepočet času nahrávky (s) na čas přehrání od startu herce: kotvy (čas nahrávky, čas přehrání) v bodech trasy, mezi
-- nimi lineárně, za poslední kotvou stejným tempem jako nahrávka.
local function timeMap(samples, points, arrive, leave, gaits)
    local t0 = samples[1].t
    local anchors = { { 0, 0 } }
    local plan = #points >= 2 and R.plan({ person = "player", points = points, speed = gaits.walk }) or nil
    if plan ~= nil then
        for k = 1, #points do
            local at = R.timeAtS(plan, plan.route.ctrlS[k] or 0)
            local ta, tl = samples[arrive[k]].t - t0, samples[leave[k]].t - t0
            local last = anchors[#anchors]
            if ta > last[1] + 1e-6 and at >= last[2] then
                anchors[#anchors + 1] = { ta, at }
            end
            if tl > ta + 1e-6 then
                anchors[#anchors + 1] = { tl, at + (points[k][4] or 0) }
            end
        end
    end
    return function(t)
        local u = t - t0
        for k = 2, #anchors do
            local a, b = anchors[k - 1], anchors[k]
            if u <= b[1] then
                local span = b[1] - a[1]
                return a[2] + (b[2] - a[2]) * (span > 1e-6 and (u - a[1]) / span or 1)
            end
        end
        local last = anchors[#anchors]
        return last[2] + (u - last[1])
    end
end

-- Křivky nesení z poloh předmětu během každého zvednutí: posun proti místu, kde ho postava drží, a natočení proti tomu,
-- jak ležel (otočení kolem svislé osy proti postavě).
local function carryCurves(samples, carries, map, opts, lastT)
    local ids, values = {}, {}
    for _, id in ipairs(opts.carryCurves) do
        ids[#ids + 1] = id
    end
    for _, id in ipairs(opts.carryTurns) do
        ids[#ids + 1] = id
    end
    for _, id in ipairs(ids) do
        values[id] = {}
    end
    for _, c in ipairs(carries) do
        local target, t1 = c.target, c.t1 or lastT
        local hx, hy, hz = opts.hold(target)
        local heldYaw = target.ry - (c.yaw or 0)
        for _, s in ipairs(samples) do
            local h = s.held
            if h ~= nil and s.t >= c.t0 - 1e-6 and s.t <= t1 + 1e-6 then
                local sn, cs = math.sin(s.yaw), math.cos(s.yaw)
                local dx, dz = h.x - s.x, h.z - s.z
                local t = map(s.t)
                local offsets = { dx * cs - dz * sn - hx, h.y - s.y - hy, dx * sn + dz * cs - hz }
                local turns = { math.deg(M.angleDiff(target.rx, h.rx)), math.deg(M.angleDiff(target.rz, h.rz)),
                    math.deg(M.angleDiff(heldYaw, h.ry - s.yaw)) }
                for k, id in ipairs(opts.carryCurves) do
                    table.insert(values[id], { t = t, v = offsets[k] })
                end
                for k, id in ipairs(opts.carryTurns) do
                    table.insert(values[id], { t = t, v = turns[k] })
                end
            end
        end
    end
    local curves = {}
    for k, id in ipairs(ids) do
        local tol = k <= #opts.carryCurves and Rc.CARRY_TOL or Rc.CARRY_TURN_TOL
        local big = false
        for _, p in ipairs(values[id]) do
            big = big or math.abs(p.v) > tol
        end
        if big then
            curves[id] = channelFrom(values[id], tol)
        end
    end
    return curves
end

-- Hotová nahrávka chůze: { person = true, points, actions, curves, duration, distance, start = { x, y, z, yaw } }; nil,
-- když postava skoro nešla a nic neudělala. opts.gaits = { slow, walk, run } (km/h temp postavy), opts.hold(target) =
-- kde postava předmět drží (x doleva, y, z dopředu), opts.carryCurves / opts.carryTurns = jména křivek nesení.
function Rc.finishPerson(rec, opts)
    local samples = rec.samples
    if #samples < 2 then
        return nil
    end
    local distance = 0
    for i = 2, #samples do
        distance = distance + math.sqrt((samples[i].x - samples[i - 1].x) ^ 2 + (samples[i].z - samples[i - 1].z) ^ 2)
    end
    if distance < Rc.MIN_DISTANCE and #rec.jumps == 0 and #rec.carries == 0 then
        return nil
    end
    local points, arrive, leave = personPoints(samples, opts.gaits)
    if distance < Rc.MIN_DISTANCE then
        points, arrive, leave = { points[1] }, { 1 }, { 1 }
        points[1][3], points[1][4] = nil, nil
    end
    local map = timeMap(samples, points, arrive, leave, opts.gaits)
    local last = samples[#samples]
    local actions = {}
    for _, t in ipairs(rec.jumps) do
        actions[#actions + 1] = { t = map(t), kind = "jump", value = 1, entry = 0 }
    end
    for _, c in ipairs(rec.carries) do
        local start = map(c.t0)
        actions[#actions + 1] = { t = start, kind = "carry", value = 1, entry = 0, carry = c.target, subLabel = c.target.name,
            dur = math.max(map(c.t1 or last.t) - start, 0.1) }
    end
    table.sort(actions, function(a, b) return a.t < b.t end)
    local first = samples[1]
    return { person = true, points = points, actions = actions, curves = carryCurves(samples, rec.carries, map, opts, last.t),
        duration = map(last.t), distance = distance, start = { x = first.x, y = first.y, z = first.z, yaw = first.yaw } }
end

---------------------------------------------------------------------------------------------------
-- Souvislý záznam přes nástup a výstup: díly po sobě (chůze, jízda, chůze…), všechny s časem vzorků od začátku záznamu.
-- Z dílů vznikne jedna postava (chůze před nástupem, akce Nastoupit a Vystoupit, chůze za výstupem jako další část trasy)
-- a vozidla jako herci, která začínají při nástupu.

local function shifted(action, dt)
    local copy = {}
    for k, v in pairs(action) do
        copy[k] = v
    end
    copy.t = action.t + dt
    return copy
end

local function appendCurves(into, from, dt)
    for id, ch in pairs(from or {}) do
        local target = into[id]
        if target == nil then
            target = Ch.new()
            into[id] = target
        end
        for _, p in ipairs(ch.points) do
            target.points[#target.points + 1] = { t = p.t + dt, v = p.v, mode = p.mode }
        end
    end
end

-- parts[i] = { kind = "walk", rec = newPerson() } nebo { kind = "drive", rec = new(), uid, name, start }; opts.person =
-- volby finishPerson, opts.driverStart = { x, y, z, yaw } (kde postava stojí, když záznam začíná ve vozidle).
-- Vrací { session = true, person = { points, curves, actions, start }, vehicles = { { name, uid, start, points, curves,
-- actions, delay, duration } }, duration }; nil, když není co uložit.
function Rc.assemble(parts, opts)
    local t0 = parts[1].rec.samples[1].t
    local person = { points = {}, curves = {}, actions = {} }
    local vehicles, started, leg, duration = {}, false, 1, 0
    for i, part in ipairs(parts) do
        local samples = part.rec.samples
        local from = samples[1].t - t0
        local nextPart = parts[i + 1]
        duration = math.max(duration, samples[#samples].t - t0)
        if part.kind == "walk" then
            local res = Rc.finishPerson(part.rec, opts.person)
            if not started then
                local s = samples[1]
                person.start = { x = s.x, y = s.y, z = s.z, yaw = s.yaw }
                person.points = res ~= nil and res.points or { { s.x, s.z } }
                if res ~= nil then
                    person.actions = res.actions
                    appendCurves(person.curves, res.curves, 0)
                end
                started = true
            elseif res ~= nil then
                res.points[1][7], res.points[1][8] = leg, true
                for _, p in ipairs(res.points) do
                    person.points[#person.points + 1] = p
                end
                for _, action in ipairs(res.actions) do
                    person.actions[#person.actions + 1] = shifted(action, from)
                end
                appendCurves(person.curves, res.curves, from)
            end
        else
            if not started then
                local s = opts.driverStart or { x = samples[1].x, y = 0, z = samples[1].z, yaw = 0 }
                person.start = { x = s.x, y = s.y, z = s.z, yaw = s.yaw }
                person.points = { { s.x, s.z } }
                started = true
            end
            local res = Rc.finish(part.rec)
            if res ~= nil then
                vehicles[#vehicles + 1] = { name = part.name, uid = part.uid, start = part.start, points = res.points,
                    curves = res.curves, actions = res.actions, delay = from, duration = res.duration }
            end
            person.actions[#person.actions + 1] = { t = from, kind = "seat", value = 1, entry = 0, vehicle = part.uid }
            if nextPart ~= nil and nextPart.kind == "walk" then
                leg = leg + 1
                person.actions[#person.actions + 1] = { t = nextPart.rec.samples[1].t - t0, kind = "seat", value = 0, entry = 0,
                    leg = leg }
            end
        end
    end
    if #vehicles == 0 and #person.points < 2 and #person.actions == 0 then
        return nil
    end
    for i, action in ipairs(person.actions) do
        action.order = i
    end
    table.sort(person.actions, function(a, b)
        if a.t ~= b.t then
            return a.t < b.t
        end
        return a.order < b.order
    end)
    for _, action in ipairs(person.actions) do
        action.order = nil
    end
    return { session = true, person = person, vehicles = vehicles, duration = duration }
end
