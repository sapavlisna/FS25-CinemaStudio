-- Záběr: bloky na časové ose kamery (shot.segments). Blok { id, t, track } trvá track.duration sekund; bloky se nepřekrývají.
-- Druhy bloků podle track.mode:
--   flight   volný let: K-framy track.keys { t (s od začátku bloku), x, y, z, q, focal, speed? }. Mezi nimi kamera jede po
--            dráze (CinemaPath) a postup řídí Hermite se sklony podle rychlosti v K-framech: přirozená (z okolních úseků),
--            nebo zadaná speed (m/s). Před prvním a za posledním K-framem stojí.
--   static   stojící kamera s pevným natočením, ostatní režimy jedou kolem objektu (CinemaModes); jejich K-framy jsou
--            značky track.marks (ohnisko, násobek rychlosti).
-- Mezera mezi bloky = kamera drží poslední pózu předchozího bloku. Na začátku bloku je střih, s track.smooth plynulé
-- navázání z pózy, kde skončil předchozí. Bez herních API.
--
-- Dál záběr nese focus (body zájmu: objekt, na který kamera v letu míří), actors (vozidla s trasou), shake (třes 0..3)
-- a env (prostředí scény, CinemaEnvironment).
--
-- Záběr může mít víc kamer (shot.cameras): každá má vlastní bloky, body zájmu, barvu a skrytí dráhy, vozidla jsou společná.
-- Pole shot.segments / focus / camColor / camHidden / curves patří vždy vybrané kameře (shot.camIndex); při přepnutí,
-- uložení a snímku se přepíšou zpět do shot.cameras.

CinemaShot = CinemaShot or {}
local S = CinemaShot
local M = CinemaMath
local P = CinemaPath

S.KEY_SNAP = 0.05 -- K-framy blíž než tohle v čase jsou tentýž K-frame (přepis místo přidání)
S.MIN_GAP = 0.1
S.MIN_SEGMENT = 1 -- nejkratší blok (s)
S.DEFAULT_PREROLL = 1.0
S.STILL_LENGTH = 0.05 -- m; úsek kratší je „jen otočení na místě" a časuje se rovnoměrně
S.SMOOTH_BLEND = 1.5 -- s; výchozí délka plynulého navázání na předchozí blok
S.FOCUS_BLEND = 1.5 -- s; jak dlouho se kamera přetáčí na nový bod zájmu
S.FOCUS_HEIGHT = 1.5 -- m nad středem objektu
S.FLIGHT = "flight"

local CAMERA_FIELDS = { "segments", "focus", "camColor", "camHidden", "curves" }

function S.new(name)
    local shot = { name = name or "shot", preroll = S.DEFAULT_PREROLL, version = 0, actors = {}, focus = {}, segments = {}, shake = 0, bank = 0,
        props = {}, objects = {} }
    shot.cameras = { { segments = shot.segments, focus = shot.focus } }
    shot.camIndex = 1
    return shot
end

-- Zapíše pole vybrané kamery zpět do jejího záznamu (volat před čtením shot.cameras).
function S.syncCamera(shot)
    local cam = shot.cameras[shot.camIndex]
    for _, f in ipairs(CAMERA_FIELDS) do
        cam[f] = shot[f]
    end
end

local function loadCamera(shot, index)
    shot.camIndex = index
    local cam = shot.cameras[index]
    for _, f in ipairs(CAMERA_FIELDS) do
        shot[f] = cam[f]
    end
    shot.version = shot.version + 1
    shot.cache = nil
end

-- Přepne na kameru číslo index; vrací false, když taková není nebo už je vybraná.
function S.setCamera(shot, index)
    if shot.cameras[index] == nil or index == shot.camIndex then
        return false
    end
    S.syncCamera(shot)
    loadCamera(shot, index)
    return true
end

-- Přidá prázdnou kameru a přepne na ni.
function S.addCamera(shot)
    S.syncCamera(shot)
    shot.cameras[#shot.cameras + 1] = { segments = {}, focus = {} }
    loadCamera(shot, #shot.cameras)
    return shot.camIndex
end

-- Smaže kameru číslo index (poslední zbývající nejde); vybraná se posune na sousední.
function S.removeCamera(shot, index)
    if #shot.cameras <= 1 or shot.cameras[index] == nil then
        return false
    end
    S.syncCamera(shot)
    table.remove(shot.cameras, index)
    loadCamera(shot, math.min(index <= shot.camIndex and math.max(shot.camIndex - 1, 1) or shot.camIndex, #shot.cameras))
    return true
end

local syncFreeKeys

local function touch(shot)
    shot.version = shot.version + 1
    shot.cache = nil
    syncFreeKeys(shot)
end
S.touch = touch

-- Stálé číslo věci na ose (K-frame, značka, akce, bod zájmu, vozidlo); přidělí se při prvním dotazu a kopie snímku ho drží.
local uidCounter = 0
function S.uid(obj)
    if obj.uid == nil then
        uidCounter = uidCounter + 1
        obj.uid = uidCounter
    end
    return obj.uid
end

local function copyTable(t)
    if type(t) ~= "table" then
        return t
    end
    local c = {}
    for k, v in pairs(t) do
        c[k] = copyTable(v)
    end
    return c
end
S.copyTable = copyTable

function S.clone(shot)
    S.syncCamera(shot)
    local c = S.new(shot.name)
    c.preroll, c.shake, c.bank, c.focusRow, c.endMark = shot.preroll, shot.shake, shot.bank, shot.focusRow, shot.endMark
    c.rowOrder = copyTable(shot.rowOrder)
    c.props, c.propsRow, c.propsCollapsed, c.fieldsOn = copyTable(shot.props) or {}, shot.propsRow, shot.propsCollapsed, shot.fieldsOn
    c.objects, c.objectsRow, c.objectsCollapsed = copyTable(shot.objects) or {}, shot.objectsRow, shot.objectsCollapsed
    c.env = copyTable(shot.env)
    c.cameras = {}
    for i, cam in ipairs(shot.cameras) do
        c.cameras[i] = { name = cam.name, camColor = cam.camColor, camHidden = cam.camHidden,
            segments = copyTable(cam.segments) or {}, focus = copyTable(cam.focus) or {}, curves = copyTable(cam.curves) }
    end
    loadCamera(c, shot.camIndex)
    c.actors = copyTable(shot.actors) or {}
    return c
end

-- Obnoví obsah ze snímku (zpět/znovu), objekt záběru zůstává stejný. S keepActors zůstanou vozidla, jak jsou
-- (při tažení se jen vrací kamera a vozidla se kvůli přepočtu tras nenahrazují).
function S.restore(shot, snapshot, keepActors)
    local c = S.clone(snapshot)
    shot.preroll, shot.shake, shot.bank, shot.focusRow, shot.endMark = c.preroll, c.shake, c.bank, c.focusRow, c.endMark
    shot.rowOrder = c.rowOrder
    shot.props, shot.propsRow, shot.propsCollapsed, shot.fieldsOn = c.props, c.propsRow, c.propsCollapsed, c.fieldsOn
    shot.objects, shot.objectsRow, shot.objectsCollapsed = c.objects, c.objectsRow, c.objectsCollapsed
    shot.env = c.env
    shot.cameras = c.cameras
    if not keepActors then
        shot.actors = c.actors
    end
    loadCamera(shot, c.camIndex)
    touch(shot)
end

-- Odstraní body zájmu a body křivek kamery v rozsahu from až to (před zavřením mezery po smazaném bloku).
function S.cutRange(shot, from, to)
    for i = #shot.focus, 1, -1 do
        local t = shot.focus[i].t
        if t >= from and t < to then
            table.remove(shot.focus, i)
        end
    end
    for _, channel in pairs(shot.curves or {}) do
        local points = channel.points or {}
        for i = #points, 1, -1 do
            if points[i].t >= from and points[i].t < to then
                table.remove(points, i)
            end
        end
    end
    touch(shot)
end

-- Posune vše od času from dál o delta (vložení do mezery, smazání se zavřením mezery): bloky, body zájmu a body křivek
-- kamery. except = věci, které se neposouvají: { segs = { [id bloku] = true }, focus = { [bod zájmu] = true } }.
function S.shiftAfter(shot, from, delta, except)
    except = except or {}
    for _, seg in ipairs(shot.segments) do
        if seg.t >= from and not (except.segs ~= nil and except.segs[seg.id]) then
            seg.t = seg.t + delta
        end
    end
    for _, f in ipairs(shot.focus) do
        if f.t >= from and not (except.focus ~= nil and except.focus[f]) then
            f.t = f.t + delta
        end
    end
    for _, channel in pairs(shot.curves or {}) do
        for _, p in ipairs(channel.points or {}) do
            if p.t >= from then
                p.t = p.t + delta
            end
        end
    end
    touch(shot)
end

-- Délka záběru: konec posledního bloku (vozidla ji můžou prodloužit v editoru).
function S.duration(shot)
    local d = 0
    for _, seg in ipairs(shot.segments) do
        d = math.max(d, S.segmentEnd(seg))
    end
    return d
end

---------------------------------------------------------------------------------------------------
-- bloky: { id, t, track }; track.duration je délka bloku

function S.segmentEnd(seg)
    return seg.t + (seg.track.duration or 0)
end

function S.isFlight(seg)
    return seg ~= nil and seg.track.mode == S.FLIGHT
end

-- Bloky s K-framy polohy a ohniska (track.keys): Let a sledování z bodu, kde natočení dodá režim (kamera míří na cíl).
S.KEYED = { flight = true, spotlight = true }

-- Odchylka směru sledování z bodu od cíle v čase rel bloku: z K-framů (aimYaw / aimPitch), mezi nimi plynule. yaw, pitch.
function S.keyAim(track, rel)
    local keys = track.keys or {}
    local n = #keys
    if n == 0 then
        return 0, 0
    end
    local function aim(k)
        return k.aimYaw or 0, k.aimPitch or 0
    end
    if rel <= keys[1].t then
        return aim(keys[1])
    end
    for i = 1, n - 1 do
        local a, b = keys[i], keys[i + 1]
        if rel <= b.t then
            local u = b.t > a.t and M.smoothstep((rel - a.t) / (b.t - a.t)) or 1
            local ay, ap = aim(a)
            local by, bp = aim(b)
            return ay + M.angleDiff(ay, by) * u, ap + (bp - ap) * u
        end
    end
    return aim(keys[n])
end

function S.hasKeys(track)
    return track ~= nil and S.KEYED[track.mode] == true and track.keys ~= nil
end

-- Sledování z bodu se stanovištěm (camX…, z režimu nebo starého záběru) dostane K-framy: na začátku stanoviště s ohniskem
-- bloku, na konci s koncovým ohniskem, liší-li se.
function S.standToKeys(track)
    if track.mode ~= "spotlight" or track.keys ~= nil or track.camX == nil then
        return
    end
    local q = M.quatFromYawPitchRoll(0, 0, 0)
    local f0 = track.focal or 35
    local f1 = track.focal2 or f0
    track.keys = { S.newKey(0, track.camX, track.camY, track.camZ, q, f0) }
    if math.abs(f1 - f0) > 0.01 and (track.duration or 0) > S.MIN_GAP then
        track.keys[2] = S.newKey(track.duration, track.camX, track.camY, track.camZ, q, f1)
    end
    track.camX, track.camY, track.camZ, track.focal2, track.marks = nil, nil, nil, nil, nil
end

-- Blok, který pokrývá čas t (včetně obou krajů), a jeho index.
function S.segmentAt(shot, t)
    for i, seg in ipairs(shot.segments) do
        if t >= seg.t - 1e-9 and t <= S.segmentEnd(seg) + 1e-9 then
            return seg, i
        end
    end
    return nil, nil
end

-- Poslední blok, který skončil nejpozději v čase t, a jeho index (mezera za ním drží jeho poslední pózu).
function S.blockBefore(shot, t)
    local found, index = nil, nil
    for i, seg in ipairs(shot.segments) do
        if S.segmentEnd(seg) <= t + 1e-9 and (found == nil or seg.t > found.t) then
            found, index = seg, i
        end
    end
    return found, index
end

-- První blok, který začíná v čase t nebo později.
function S.blockAfter(shot, t)
    local found, index = nil, nil
    for i, seg in ipairs(shot.segments) do
        if seg.t >= t - 1e-9 and (found == nil or seg.t < found.t) then
            found, index = seg, i
        end
    end
    return found, index
end

function S.nextSegmentId(shot)
    local id = 0
    for _, seg in ipairs(shot.segments) do
        id = math.max(id, seg.id or 0)
    end
    return id + 1
end

-- Překrývá blok jiný blok?
function S.segmentOverlaps(shot, seg)
    for _, other in ipairs(shot.segments) do
        if other ~= seg and other.id ~= seg.id and seg.t < S.segmentEnd(other) + S.KEY_SNAP and other.t < S.segmentEnd(seg) + S.KEY_SNAP then
            return true
        end
    end
    return false
end

function S.sortSegments(shot)
    table.sort(shot.segments, function(a, b) return a.t < b.t end)
end

-- Vloží blok na místo podle času; vrací jeho index.
function S.addSegment(shot, seg)
    local index = #shot.segments + 1
    for i, other in ipairs(shot.segments) do
        if other.t > seg.t then
            index = i
            break
        end
    end
    table.insert(shot.segments, index, seg)
    touch(shot)
    return index
end

function S.removeSegment(shot, index)
    if shot.segments[index] == nil then
        return false
    end
    table.remove(shot.segments, index)
    touch(shot)
    return true
end

-- Meze pro posun začátku bloku, aby nepřejel přes jiné bloky.
function S.segmentBounds(shot, seg)
    local lo, hi = 0, math.huge
    local dur = seg.track.duration or 0
    for _, other in ipairs(shot.segments) do
        if other.id ~= seg.id then
            if other.t < seg.t then
                lo = math.max(lo, S.segmentEnd(other) + S.MIN_GAP)
            else
                hi = math.min(hi, other.t - dur - S.MIN_GAP)
            end
        end
    end
    return lo, hi
end

function S.moveSegment(shot, seg, t)
    local lo, hi = S.segmentBounds(shot, seg)
    if lo > hi then
        return seg.t
    end
    seg.t = M.clamp(t, lo, hi)
    touch(shot)
    return seg.t
end

-- Blok a jeho index podle čísla bloku.
function S.segmentById(shot, id)
    for i, seg in ipairs(shot.segments) do
        if seg.id == id then
            return seg, i
        end
    end
    return nil, nil
end

-- Kam až se smí blok natáhnout: nejdřív začátek a nejpozději konec, aby nepřejel přes jiné bloky.
function S.segmentLimits(shot, seg)
    local lo, hi = 0, math.huge
    for _, other in ipairs(shot.segments) do
        if other.id ~= seg.id then
            if other.t < seg.t then
                lo = math.max(lo, S.segmentEnd(other) + S.MIN_GAP)
            else
                hi = math.min(hi, other.t - S.MIN_GAP)
            end
        end
    end
    return lo, hi
end

-- Ořez bloku za jeho kraj: edge = "start" posune začátek (konec stojí), "end" konec. Let si nechá pohyb, jak byl: zkrácením
-- se K-framy za novým krajem zahodí a na kraji vznikne K-frame s pózou, kterou tam kamera měla; natažením kamera na kraji stojí.
function S.resizeSegment(shot, seg, edge, t)
    local lo, hi = S.segmentLimits(shot, seg)
    local start, finish = seg.t, S.segmentEnd(seg)
    local track = seg.track
    if edge == "start" then
        local newStart = M.clamp(t, math.min(lo, finish - S.MIN_SEGMENT), finish - S.MIN_SEGMENT)
        if S.hasKeys(track) then
            local delta = newStart - start
            if delta > 0 then
                track.keys = S.flightPiece(shot, track, delta, finish - start).keys
            else
                for _, k in ipairs(track.keys) do
                    k.t = k.t - delta
                end
            end
        end
        seg.t = newStart
    else
        local newFinish = M.clamp(t, seg.t + S.MIN_SEGMENT, math.max(hi, seg.t + S.MIN_SEGMENT))
        if S.hasKeys(track) and newFinish < finish then
            track.keys = S.flightPiece(shot, track, 0, newFinish - start).keys
        end
        finish = newFinish
    end
    track.duration = finish - seg.t
    touch(shot)
    return seg.t, finish
end

-- Délka bloku vydělená factor (factor > 1 = rychleji); u Letu se úměrně zkrátí časy K-framů.
function S.scaleSegment(shot, seg, factor)
    local track = seg.track
    local _, hi = S.segmentLimits(shot, seg)
    local duration = math.max((track.duration or 1) / factor, S.MIN_SEGMENT)
    duration = math.min(duration, math.max(hi - seg.t, S.MIN_SEGMENT))
    local scale = duration / math.max(track.duration or 1, 1e-6)
    if S.hasKeys(track) then
        for _, k in ipairs(track.keys) do
            k.t = k.t * scale
            if k.speed ~= nil then
                k.speed = k.speed / scale
            end
        end
    end
    track.duration = duration
    touch(shot)
    return duration
end

---------------------------------------------------------------------------------------------------
-- Let: K-framy v bloku

function S.newKey(t, x, y, z, q, focal)
    return { t = t, x = x, y = y, z = z, q = { q[1], q[2], q[3], q[4] }, focal = focal }
end

local function copyKey(k)
    local c = S.newKey(k.t, k.x, k.y, k.z, k.q, k.focal)
    c.speed, c.uid, c.infIn, c.infOut, c.free = k.speed, k.uid, k.infIn, k.infOut, k.free
    c.aimYaw, c.aimPitch = k.aimYaw, k.aimPitch
    c.hin = k.hin and { k.hin[1], k.hin[2], k.hin[3] }
    c.hout = k.hout and { k.hout[1], k.hout[2], k.hout[3] }
    return c
end
S.copyKey = copyKey

-- Nový Let s jedním K-framem na začátku.
function S.newFlight(key, duration)
    key.t = 0
    return { mode = S.FLIGHT, duration = duration or S.MIN_SEGMENT, keys = { key } }
end

-- tau, ve kterém easeBezier dosáhne postupu p (průběh je neklesající).
local function invertEase(p, m0, m1, a, b)
    local lo, hi = 0, 1
    for _ = 1, 40 do
        local mid = (lo + hi) * 0.5
        if M.easeBezier(mid, m0, m1, a, b) < p then
            lo = mid
        else
            hi = mid
        end
    end
    return (lo + hi) * 0.5
end

-- Mezipaměť dráhy a sklonů Letu; platí do další změny záběru (S.touch). Úseky průběhu (c.m0 … c.b) jsou mezi
-- pevnými K-framy (c.anchors), c.group[i] je úsek, do kterého patří dráha za K-framem i.
local function buildFlight(track)
    local keys = track.keys
    local n = #keys
    local c = { ts = {}, quats = {}, focal = {}, pts = {}, handles = {}, speed = {}, limit = {}, cum = {}, free = {},
        anchors = {}, group = {}, m0 = {}, m1 = {}, a = {}, b = {} }
    for i, k in ipairs(keys) do
        c.ts[i] = k.t
        c.pts[i] = { k.x, k.y, k.z }
        c.handles[i] = { hin = k.hin, hout = k.hout }
        c.quats[i] = k.q
        -- ohnisko v logaritmu: zoom 24→200 mm pak působí rovnoměrně, ne „rychle na začátku"
        c.focal[i] = { math.log(k.focal) }
    end
    c.quats = M.alignQuats(c.quats)
    if n < 2 then
        c.speed[1], c.limit[1] = 0, 0
        return c
    end
    c.path = P.build(c.pts, c.handles)
    c.cum[1] = 0
    for i = 1, n - 1 do
        c.cum[i + 1] = c.cum[i] + P.segmentLength(c.path, i)
    end
    -- K-frame jen natočení nemá vlastní čas ani rychlost: kamera jím projede rychlostí mezi pevnými sousedy.
    -- Kraje Letu a K-framy u otočení na místě jsou vždy pevné.
    for i = 1, n do
        local free = keys[i].free and i > 1 and i < n
            and P.segmentLength(c.path, i - 1) > S.STILL_LENGTH and P.segmentLength(c.path, i) > S.STILL_LENGTH
        if free then
            c.free[i] = true
        else
            c.anchors[#c.anchors + 1] = i
        end
    end
    local A = c.anchors
    local na = #A
    local function len(g)
        return c.cum[A[g + 1]] - c.cum[A[g]]
    end
    local function dur(g)
        return c.ts[A[g + 1]] - c.ts[A[g]]
    end
    for g = 1, na - 1 do
        c.a[g] = S.influence(keys[A[g]], "out")
        c.b[g] = S.influence(keys[A[g + 1]], "in")
        for i = A[g], A[g + 1] - 1 do
            c.group[i] = g
        end
    end
    for g = 1, na do
        local dl, dt = 0, 0
        if g > 1 then
            dl, dt = dl + len(g - 1), dt + dur(g - 1)
        end
        if g < na then
            dl, dt = dl + len(g), dt + dur(g)
        end
        local natural = dt > 0 and dl / dt or 0
        -- strop (1 / vliv)× průměr sousedního úseku drží postup monotónní; uplatní se na společnou rychlost K-framu,
        -- ne na každou stranu zvlášť, jinak by se rychlost v K-framu skokem změnila
        local limit = math.huge
        for _, j in ipairs({ g - 1, g }) do
            if j >= 1 and j < na then
                local sl, st = len(j), dur(j)
                if sl > S.STILL_LENGTH and st > 0 then
                    local inf = j == g and c.a[j] or c.b[j]
                    limit = math.min(limit, sl / st / inf)
                end
            end
        end
        if limit == math.huge then
            limit = 0
        end
        local i = A[g]
        c.limit[i] = limit
        local wanted = keys[i].speed or natural
        c.speed[i] = M.clamp(wanted, 0, limit)
    end
    for g = 1, na - 1 do
        local i, j = A[g], A[g + 1]
        local dl, dt = len(g), dur(g)
        local a, b = 1, 1
        if dl > S.STILL_LENGTH and dt > 0 then
            a, b = c.speed[i] * dt / dl, c.speed[j] * dt / dl
        else
            -- otočení na místě: zastavení v K-framu (rychlost 0) zpomalí i otáčení
            a, b = keys[i].speed == 0 and 0 or 1, keys[j].speed == 0 and 0 or 1
        end
        c.m0[g] = M.clamp(a, 0, 1 / c.a[g])
        c.m1[g] = M.clamp(b, 0, 1 / c.b[g])
        for f = i + 1, j - 1 do
            local tau = invertEase((c.cum[f] - c.cum[i]) / dl, c.m0[g], c.m1[g], c.a[g], c.b[g])
            c.ts[f] = c.ts[i] + tau * dt
            c.speed[f] = dl * M.easeBezierDerivative(tau, c.m0[g], c.m1[g], c.a[g], c.b[g]) / dt
            c.limit[f] = c.speed[f]
        end
    end
    return c
end

-- Vliv K-framu na straně side ("in" = příjezd, "out" = odjezd): jakou část úseku trvá změna rychlosti.
function S.influence(key, side)
    local v = side == "in" and key.infIn or key.infOut
    return M.clamp(v or M.INFLUENCE, M.INFLUENCE_MIN, M.INFLUENCE_MAX)
end

local function flightCache(shot, track)
    local caches = shot.cache
    if caches == nil then
        caches = {}
        shot.cache = caches
    end
    local c = caches[track]
    if c == nil then
        c = buildFlight(track)
        caches[track] = c
    end
    return c
end

-- Časy K-framů jen natočení podle průběhu, aby je osa a hledání K-framu viděly tam, kudy kamera opravdu projede.
syncFreeKeys = function(shot)
    for _, seg in ipairs(shot.segments or {}) do
        local keys = S.hasKeys(seg.track) and seg.track.keys or {}
        for _, k in ipairs(keys) do
            if k.free then
                local c = flightCache(shot, seg.track)
                for i in pairs(c.free) do
                    keys[i].t = c.ts[i]
                end
                break
            end
        end
    end
end

-- Úsek dráhy a postup v něm v čase rel (s od začátku bloku): i, f (postup po easingu, 0..1), g (úsek průběhu)
-- a tau (čas v úseku průběhu, 0..1).
local function flightSpan(c, n, rel)
    local i
    if rel <= c.ts[1] then
        i = 1
    elseif rel >= c.ts[n] then
        i = n - 1
    else
        i = M.findSegment(c.ts, rel)
    end
    local g = c.group[i]
    local s, e = c.anchors[g], c.anchors[g + 1]
    local tau = M.clamp((rel - c.ts[s]) / (c.ts[e] - c.ts[s]), 0, 1)
    local F = M.easeBezier(tau, c.m0[g], c.m1[g], c.a[g], c.b[g])
    if e - s == 1 then
        return i, F, g, tau
    end
    local d = c.cum[s] + F * (c.cum[e] - c.cum[s])
    i = s
    while i < e - 1 and c.cum[i + 1] < d do
        i = i + 1
    end
    local sl = c.cum[i + 1] - c.cum[i]
    return i, sl > 0 and M.clamp((d - c.cum[i]) / sl, 0, 1) or 0, g, tau
end

-- Póza Letu v čase rel: x, y, z, kvaternion, ohnisko; nil bez K-framů.
function S.flightEvaluate(shot, track, rel)
    local keys = track.keys
    local n = #keys
    if n == 0 then
        return nil
    end
    if n == 1 then
        local k = keys[1]
        return k.x, k.y, k.z, M.quatNormalize(k.q), k.focal
    end
    local c = flightCache(shot, track)
    local i, f = flightSpan(c, n, rel)
    local x, y, z = P.pointInSegment(c.path, i, f * P.segmentLength(c.path, i))
    -- natočení a ohnisko jedou ve stejném postupu jako poloha: zastaví-li kamera v bodě, zastaví i otáčení
    local tr = c.ts[i] + f * (c.ts[i + 1] - c.ts[i])
    local q = M.quatHermite(c.ts, c.quats, tr)
    local focal = math.exp(M.hermite(c.ts, c.focal, 1, tr)[1])
    return x, y, z, q, focal
end

-- Rychlost po dráze Letu v čase rel (m/s); mimo K-framy 0.
function S.flightSpeedAt(shot, track, rel)
    local n = #track.keys
    if n < 2 then
        return 0
    end
    local c = flightCache(shot, track)
    if rel < c.ts[1] or rel > c.ts[n] then
        return 0
    end
    local _, _, g, tau = flightSpan(c, n, rel)
    local s, e = c.anchors[g], c.anchors[g + 1]
    return (c.cum[e] - c.cum[s]) * M.easeBezierDerivative(tau, c.m0[g], c.m1[g], c.a[g], c.b[g]) / (c.ts[e] - c.ts[s])
end

-- Rychlost v K-framu i (m/s), jak se opravdu jede, a nejvyšší, jakou může mít (kamera pak nikdy necouvá).
function S.keySpeed(shot, track, i)
    local c = flightCache(shot, track)
    return c.speed[i] or 0, c.limit[i] or 0
end

-- Je K-frame i jen natočení (čas a rychlost v něm určí pevní sousedé)?
function S.keyIsFree(shot, track, i)
    return #track.keys >= 2 and flightCache(shot, track).free[i] == true
end

-- Sousední pevný K-frame před (dir -1) nebo za (dir 1) K-framem i, nebo nil.
function S.anchorNeighbor(shot, track, i, dir)
    local j = i + dir
    while track.keys[j] ~= nil and S.keyIsFree(shot, track, j) do
        j = j + dir
    end
    return track.keys[j] ~= nil and j or nil
end

-- Přepne K-frame na „jen natočení“ (on) nebo zpět na vlastní čas a rychlost; vlastní rychlost a vliv zahodí.
function S.setKeyFree(shot, key, on)
    key.free = on or nil
    if on then
        key.speed, key.infIn, key.infOut = nil, nil, nil
    end
    touch(shot)
end

-- Zadá rychlost v K-framu (m/s; nil = přirozená podle okolních úseků). K-frame jen natočení rychlost nemá.
function S.setKeySpeed(shot, track, i, v)
    local k = track.keys[i]
    if k == nil or S.keyIsFree(shot, track, i) then
        return false
    end
    if v == nil then
        k.speed = nil
    else
        local _, limit = S.keySpeed(shot, track, i)
        k.speed = M.clamp(v, 0, limit)
    end
    touch(shot)
    return true
end

function S.flightLength(shot, track)
    if #track.keys < 2 then
        return 0
    end
    return flightCache(shot, track).path.length
end

-- Průměrná rychlost Letu mezi prvním a posledním K-framem (m/s).
function S.flightAverage(shot, track)
    local keys = track.keys
    local span = #keys >= 2 and keys[#keys].t - keys[1].t or 0
    return span > 0 and S.flightLength(shot, track) / span or 0
end

-- Index K-framu v čase rel (s tolerancí), nebo nil.
function S.flightKeyAt(track, rel)
    for i, k in ipairs(track.keys) do
        if math.abs(k.t - rel) <= S.KEY_SNAP then
            return i
        end
    end
    return nil
end

-- Přidá K-frame, nebo přepíše ten v tomtéž čase (jeho rychlost a číslo zůstanou). Vrací index.
function S.flightSetKey(shot, track, key)
    key.t = M.clamp(key.t, 0, track.duration or key.t)
    local existing = S.flightKeyAt(track, key.t)
    if existing ~= nil then
        local old = track.keys[existing]
        key.t, key.speed, key.uid = old.t, old.speed, old.uid
        key.infIn, key.infOut, key.hin, key.hout, key.free = old.infIn, old.infOut, old.hin, old.hout, old.free
        track.keys[existing] = key
        touch(shot)
        return existing
    end
    local index = #track.keys + 1
    for i, k in ipairs(track.keys) do
        if k.t > key.t then
            index = i
            break
        end
    end
    table.insert(track.keys, index, key)
    touch(shot)
    return index
end

function S.flightRemoveKey(shot, track, index)
    if track.keys[index] == nil then
        return false
    end
    table.remove(track.keys, index)
    touch(shot)
    return true
end

-- Posun K-framu v čase uvnitř bloku; nepřeskočí sousedy ani kraje bloku. Vrací nový čas. K-frame jen natočení
-- se neposune, jeho čas určuje průběh.
function S.flightMoveKey(shot, track, index, rel)
    local keys = track.keys
    local k = keys[index]
    if k == nil then
        return nil
    end
    if S.keyIsFree(shot, track, index) then
        return k.t
    end
    local lo = index > 1 and keys[index - 1].t + S.MIN_GAP or 0
    local hi = index < #keys and keys[index + 1].t - S.MIN_GAP or (track.duration or rel)
    if lo > hi then
        return k.t
    end
    k.t = M.clamp(rel, lo, hi)
    touch(shot)
    return k.t
end

function S.nudgeKey(shot, key, dx, dy, dz)
    key.x, key.y, key.z = key.x + dx, key.y + dy, key.z + dz
    touch(shot)
end

-- Natočení K-framu o dyaw / dpitch (rad); kladný pitch je pohled dolů.
function S.turnKey(shot, key, dyaw, dpitch)
    local yaw, pitch, roll = M.quatToYawPitchRoll(key.q)
    key.q = M.quatFromYawPitchRoll(yaw + dyaw, M.clamp(pitch + dpitch, -math.rad(89), math.rad(89)), roll)
    touch(shot)
end

-- Úsek Letu from..to (s od začátku bloku) jako nový Let: K-framy uvnitř se posunou, na krajích uvnitř dráhy vzniknou
-- K-framy s pózou a rychlostí, kterou tam kamera měla, takže pohyb zůstane. Bez stálých čísel (uid).
function S.flightPiece(shot, track, from, to)
    local piece = {}
    for k, v in pairs(track) do
        if k ~= "keys" then
            piece[k] = copyTable(v)
        end
    end
    piece.duration = to - from
    piece.keys = {}
    local keys = track.keys
    local n = #keys
    local first, last = keys[1].t, keys[n].t
    local function boundary(at)
        local x, y, z, q, focal = S.flightEvaluate(shot, track, at)
        local k = S.newKey(at - from, x, y, z, q, focal)
        if at > first and at < last then
            k.speed = S.flightSpeedAt(shot, track, at)
        end
        if track.mode == "spotlight" then
            k.aimYaw, k.aimPitch = S.keyAim(track, at)
        end
        piece.keys[#piece.keys + 1] = k
    end
    if from > first + S.KEY_SNAP and S.flightKeyAt(track, from) == nil then
        boundary(from)
    end
    for _, k in ipairs(keys) do
        if k.t >= from - S.KEY_SNAP and k.t <= to + S.KEY_SNAP then
            local c = copyKey(k)
            c.uid = nil
            c.t = M.clamp(k.t - from, 0, to - from)
            piece.keys[#piece.keys + 1] = c
        end
    end
    if to < last - S.KEY_SNAP and S.flightKeyAt(track, to) == nil then
        boundary(to)
    end
    if #piece.keys == 0 then
        boundary(from)
        piece.keys[1].t = 0
    end
    return piece
end

-- Stálá rychlost Letu při zachované délce: časy K-framů podle ujeté dráhy, zadané rychlosti pryč.
-- Úseky „jen otočení na místě" si nechají svou délku.
function S.flightConstantSpeed(shot, track)
    local keys = track.keys
    local n = #keys
    for _, k in ipairs(keys) do
        k.speed = nil
    end
    if n < 3 then
        touch(shot)
        return n == 2
    end
    local c = flightCache(shot, track)
    local total = keys[n].t - keys[1].t
    local fixed, moving = 0, 0
    for i = 1, n - 1 do
        local dl = P.segmentLength(c.path, i)
        if dl <= S.STILL_LENGTH then
            fixed = fixed + (keys[i + 1].t - keys[i].t)
        else
            moving = moving + dl
        end
    end
    local available = total - fixed
    if moving <= 0 or available <= 0 then
        touch(shot)
        return false
    end
    local durations = {}
    for i = 1, n - 1 do
        local dl = P.segmentLength(c.path, i)
        if dl <= S.STILL_LENGTH then
            durations[i] = keys[i + 1].t - keys[i].t
        else
            durations[i] = math.max(available * dl / moving, S.MIN_GAP)
        end
    end
    local t = keys[1].t
    for i = 2, n do
        t = t + durations[i - 1]
        keys[i].t = t
    end
    touch(shot)
    return true
end

---------------------------------------------------------------------------------------------------
-- Průjezd K-framem, úseky a průběh Letu

S.PASSES = { "auto", "stop", "corner" }
S.RAMP_SHARE = 0.3
S.RAMP_STEP = 0.5
S.HUMP_SAMPLES = 24
S.HUMP_RATIO = 1.08
S.HUMP_MIN = 0.1
S.INFLUENCE_PRESETS = { short = 0.15, medium = M.INFLUENCE, long = 0.7 }

local function isZero(h)
    return h ~= nil and math.abs(h[1]) + math.abs(h[2]) + math.abs(h[3]) < 1e-6
end

-- Průjezd K-framem: "stop" (rychlost 0), "corner" (obě táhla nulová), "custom" (vlastní táhla), jinak "auto".
function S.keyPass(key)
    if key.speed == 0 then
        return "stop"
    elseif isZero(key.hin) and isZero(key.hout) then
        return "corner"
    elseif key.hin ~= nil or key.hout ~= nil then
        return "custom"
    end
    return "auto"
end

-- Plynule: oblouk a rychlost podle okolí. Zastavit: rychlost 0, tvar dráhy zůstane. Roh: rovně do bodu i z bodu.
function S.setKeyPass(shot, key, pass)
    if pass == "stop" then
        key.speed, key.free = 0, nil
    elseif pass == "corner" then
        key.speed = nil
        key.hin, key.hout = { 0, 0, 0 }, { 0, 0, 0 }
    else
        key.speed, key.hin, key.hout, key.infIn, key.infOut = nil, nil, nil, nil, nil
    end
    touch(shot)
end

-- Další volba průjezdu v pořadí Plynule → Zastavit → Roh → Plynule.
function S.cyclePass(shot, key)
    local current = S.keyPass(key)
    local nextPass = "auto"
    for i, p in ipairs(S.PASSES) do
        if p == current then
            nextPass = S.PASSES[i % #S.PASSES + 1]
        end
    end
    S.setKeyPass(shot, key, nextPass)
    return nextPass
end

-- Vliv K-framu (nil = výchozí) na jedné straně ("in" / "out"), nebo na obou (side nil).
function S.setKeyInfluence(shot, key, side, value)
    if value ~= nil then
        value = M.clamp(value, M.INFLUENCE_MIN, M.INFLUENCE_MAX)
    end
    if side ~= "out" then
        key.infIn = value
    end
    if side ~= "in" then
        key.infOut = value
    end
    touch(shot)
end

-- Index úseku Letu (mezi K-framy i a i + 1) v čase rel, nebo nil.
function S.flightSpanAt(track, rel)
    local keys = track.keys
    for i = 1, #keys - 1 do
        if rel >= keys[i].t and rel <= keys[i + 1].t then
            return i
        end
    end
    return nil
end

-- Tvar úseku i: "straight" (přímka), "curve" (oblouk), "stops" (z bodu do bodu), "constant" (stálou rychlostí).
function S.setSpanShape(shot, track, i, shape)
    local a, b = track.keys[i], track.keys[i + 1]
    if a == nil or b == nil then
        return false
    end
    if shape == "straight" then
        a.hout, b.hin = { 0, 0, 0 }, { 0, 0, 0 }
    elseif shape == "curve" then
        a.hout, b.hin = nil, nil
        if a.hin ~= nil and isZero(a.hin) then
            a.hin = nil
        end
        if b.hout ~= nil and isZero(b.hout) then
            b.hout = nil
        end
    elseif shape == "stops" then
        a.speed, b.speed = 0, 0
        a.free, b.free = nil, nil
    elseif shape == "constant" then
        a.free, b.free = nil, nil
        touch(shot)
        local c = flightCache(shot, track)
        local dt = b.t - a.t
        local v = dt > 0 and P.segmentLength(c.path, i) / dt or 0
        a.speed, b.speed = v, v
        a.infOut, b.infIn = nil, nil
    end
    touch(shot)
    return true
end

function S.spanIsStraight(track, i)
    local a, b = track.keys[i], track.keys[i + 1]
    return a ~= nil and b ~= nil and isZero(a.hout) and isZero(b.hin)
end

-- Hladký rozjezd za rin s, stálá rychlost a hladký dojezd za rout s v čase t z total: rychlost a ujetá dráha
-- v násobcích nejvyšší rychlosti.
local function rampSpeed(t, total, rin, rout)
    if rin > 0 and t < rin then
        local u = t / rin
        return u * u * (3 - 2 * u)
    elseif rout > 0 and t > total - rout then
        local u = (total - t) / rout
        return u * u * (3 - 2 * u)
    end
    return 1
end

local function rampDistance(t, total, rin, rout)
    local function part(u, r)
        return r * (u ^ 3 - u ^ 4 / 2)
    end
    if rin > 0 and t < rin then
        return part(t / rin, rin)
    end
    local d = rin / 2 + math.min(t, total - rout) - rin
    if rout > 0 and t > total - rout then
        d = d + rout / 2 - part((total - t) / rout, rout)
    end
    return d
end

-- Časy pevných K-framů podle průběhu rychlosti (rozjezd track.rampIn s, stálá rychlost, dojezd track.rampOut s)
-- při zachované dráze a délce Letu; K-framy dostanou rychlost, kterou jimi kamera projede. Pevné časy u otočení
-- na místě by zaručeně udělaly kopeček (úsek musí stihnout dráhu za daný čas), proto se mění časy, ne rychlosti.
function S.retimeFlight(shot, track)
    local keys = track.keys
    local n = #keys
    if n < 2 then
        return false
    end
    touch(shot)
    local c = flightCache(shot, track)
    local A = c.anchors
    local still, moving = 0, 0
    for g = 1, #A - 1 do
        local dl = c.cum[A[g + 1]] - c.cum[A[g]]
        if dl <= S.STILL_LENGTH then
            still = still + keys[A[g + 1]].t - keys[A[g]].t
        else
            moving = moving + dl
        end
    end
    local span = keys[n].t - keys[1].t - still
    if moving <= 0 or span <= 0 then
        return false
    end
    local rin, rout = math.max(track.rampIn or 0, 0), math.max(track.rampOut or 0, 0)
    if rin + rout > span then
        rin, rout = rin * span / (rin + rout), rout * span / (rin + rout)
    end
    local vmax = moving / (span - rin / 2 - rout / 2)
    local times, taus = { keys[1].t }, { 0 }
    local t, tau, d = keys[1].t, 0, 0
    for g = 1, #A - 1 do
        local i, j = A[g], A[g + 1]
        local dl = c.cum[j] - c.cum[i]
        if dl <= S.STILL_LENGTH then
            t = t + keys[j].t - keys[i].t
        else
            d = d + dl
            local lo, hi = tau, span
            for _ = 1, 50 do
                local mid = (lo + hi) * 0.5
                if rampDistance(mid, span, rin, rout) * vmax < d then
                    lo = mid
                else
                    hi = mid
                end
            end
            local nt = g == #A - 1 and span or (lo + hi) * 0.5
            t, tau = t + nt - tau, nt
        end
        times[g + 1], taus[g + 1] = t, tau
    end
    for g, i in ipairs(A) do
        local k = keys[i]
        k.t = times[g]
        k.speed = vmax * rampSpeed(taus[g], span, rin, rout)
        k.infIn, k.infOut = nil, nil
    end
    touch(shot)
    return true
end

-- Rozjezd (side "in") nebo dojezd ("out") Letu v s; 0 = bez něj. Časy K-framů se hned přepočítají.
function S.setFlightRamp(shot, track, side, seconds)
    local span = #track.keys >= 2 and track.keys[#track.keys].t - track.keys[1].t or 0
    seconds = M.clamp(seconds, 0, span)
    if side == "in" then
        track.rampIn = seconds
    else
        track.rampOut = seconds
    end
    return S.retimeFlight(shot, track)
end

-- Úseky, kde rychlost uprostřed vyletí nad rychlost v obou krajních K-framech (kopeček): { from, to, peak }
-- v s od začátku bloku.
function S.flightHumps(shot, track)
    local out = {}
    if #track.keys < 2 then
        return out
    end
    local c = flightCache(shot, track)
    local A = c.anchors
    for g = 1, #A - 1 do
        local i, j = A[g], A[g + 1]
        local edge = math.max(c.speed[i] or 0, c.speed[j] or 0)
        local peak = 0
        for k = 1, S.HUMP_SAMPLES - 1 do
            local v = (c.cum[j] - c.cum[i]) * M.easeBezierDerivative(k / S.HUMP_SAMPLES, c.m0[g], c.m1[g], c.a[g], c.b[g])
                / (c.ts[j] - c.ts[i])
            peak = math.max(peak, v)
        end
        if peak > edge * S.HUMP_RATIO + S.HUMP_MIN then
            out[#out + 1] = { from = c.ts[i], to = c.ts[j], peak = peak }
        end
    end
    return out
end

-- Průběh celého Letu: "constant" (stálá rychlost), "uniform" (stálá rychlost, vnitřní K-framy jen natočení),
-- "easeInOut" (pomalý nájezd a dojezd), "accelerate" (ze stání), "decelerate" (do zastavení). Nájezd a dojezd
-- trvají S.RAMP_SHARE délky Letu (nebo co je v bloku nastavené) a časy K-framů se jim přizpůsobí.
function S.setFlightProfile(shot, track, profile)
    local keys = track.keys
    local n = #keys
    if n < 2 then
        return false
    end
    track.rampIn, track.rampOut = nil, nil
    if profile == "constant" then
        return S.flightConstantSpeed(shot, track)
    end
    if profile == "uniform" then
        for i, k in ipairs(keys) do
            k.speed, k.infIn, k.infOut = nil, nil, nil
            k.free = (i > 1 and i < n) or nil
        end
        touch(shot)
        return true
    end
    local ramp = (keys[n].t - keys[1].t) * S.RAMP_SHARE
    if profile == "easeInOut" or profile == "accelerate" then
        track.rampIn = ramp
    end
    if profile == "easeInOut" or profile == "decelerate" then
        track.rampOut = ramp
    end
    return S.retimeFlight(shot, track)
end

-- Skutečná táhla K-framu i (vstup, výstup) relativně k němu, i automatická.
function S.keyHandles(shot, track, i)
    if #track.keys < 2 then
        return { 0, 0, 0 }, { 0, 0, 0 }
    end
    local c = flightCache(shot, track)
    return c.path.hin[i], c.path.hout[i]
end

-- Táhlo K-framu i na straně side nastaví na vektor v (m, relativně k bodu). S aligned se druhé táhlo natočí
-- opačným směrem a nechá si délku, takže oblouk zůstane hladký.
function S.setKeyHandle(shot, track, i, side, v, aligned)
    local key = track.keys[i]
    if key == nil then
        return
    end
    local hin, hout = S.keyHandles(shot, track, i)
    local other = side == "in" and hout or hin
    local own = { v[1], v[2], v[3] }
    if aligned then
        local len = math.sqrt(own[1] ^ 2 + own[2] ^ 2 + own[3] ^ 2)
        local olen = math.sqrt(other[1] ^ 2 + other[2] ^ 2 + other[3] ^ 2)
        if len > 1e-6 then
            other = { -own[1] / len * olen, -own[2] / len * olen, -own[3] / len * olen }
        end
    end
    if side == "in" then
        key.hin, key.hout = own, { other[1], other[2], other[3] }
    else
        key.hout, key.hin = own, { other[1], other[2], other[3] }
    end
    touch(shot)
end

-- Body dráhy Letu pro náhled (podle vzdálenosti, ne času, aby byla vidět i místa, kde kamera stojí).
function S.flightPath(shot, track, step)
    local out = {}
    if #track.keys < 2 then
        return out
    end
    local path = flightCache(shot, track).path
    local s = 0
    while s < path.length do
        local x, y, z = P.pointAt(path, s)
        out[#out + 1] = { x, y, z }
        s = s + step
    end
    local x, y, z = P.pointAt(path, path.length)
    out[#out + 1] = { x, y, z }
    return out
end

-- Časy K-framů bloku od jeho začátku: u Letu jeho K-framy, u režimů značky.
function S.kframeTimes(seg)
    local list = {}
    local track = seg.track
    if S.hasKeys(track) then
        for _, k in ipairs(track.keys) do
            list[#list + 1] = k.t
        end
    else
        for _, m in ipairs(track.marks or {}) do
            list[#list + 1] = m.u * (track.duration or 0)
        end
    end
    return list
end

-- Všechny K-framy bloků s polohou (Let, sledování z bodu) jako { key, seg, index, t (čas záběru) } seřazené podle času.
function S.allKeys(shot)
    local list = {}
    for _, seg in ipairs(shot.segments) do
        if S.hasKeys(seg.track) then
            for i, k in ipairs(seg.track.keys) do
                list[#list + 1] = { key = k, seg = seg, index = i, t = seg.t + k.t }
            end
        end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    return list
end

---------------------------------------------------------------------------------------------------
-- body zájmu: { t, target (uid | nil = volně podle K-framů), height, blend }

-- Přidá bod zájmu, nebo přepíše ten v tomtéž čase (doba přechodu zůstane). Vrací index.
function S.setFocus(shot, t, target, height)
    t = math.max(0, t)
    for i, f in ipairs(shot.focus) do
        if math.abs(f.t - t) <= S.KEY_SNAP then
            f.target, f.height = target, height or f.height
            touch(shot)
            return i
        end
    end
    local index = #shot.focus + 1
    for i, f in ipairs(shot.focus) do
        if f.t > t then
            index = i
            break
        end
    end
    table.insert(shot.focus, index, { t = t, target = target, height = height or S.FOCUS_HEIGHT, blend = S.FOCUS_BLEND })
    touch(shot)
    return index
end

S.FOCUS_DURATION = 2 -- s; jak dlouho míří nově přidaný bod zájmu (konec se táhne jako u bloku)

-- Nový bod zájmu jako blok: od t míří na target dur sekund, pak se vrátí k tomu, co platilo předtím (jiný cíl, nebo volný
-- pohled). Konec je další bod zájmu, takže se délka mění jeho tažením. Přepis bodu v tomtéž čase konec nepřidá. Vrací index.
function S.addFocusBlock(shot, t, target, dur)
    t = math.max(0, t)
    dur = dur or S.FOCUS_DURATION
    local before = S.focusIndexAt(shot, t - S.KEY_SNAP - 1e-6)
    local resume = before ~= nil and shot.focus[before].target or nil
    local existed = false
    for _, f in ipairs(shot.focus) do
        existed = existed or math.abs(f.t - t) <= S.KEY_SNAP
    end
    local index = S.setFocus(shot, t, target)
    local nextF = shot.focus[index + 1]
    if target ~= nil and not existed and (nextF == nil or nextF.t > t + dur + S.MIN_GAP) then
        local endIndex = S.setFocus(shot, t + dur, resume)
        if resume == nil then
            -- návrat do volného pohledu bez dlouhého přetáčení
            shot.focus[endIndex].blend = S.FOCUS_BLEND
        end
    end
    return index
end

function S.removeFocus(shot, index)
    if shot.focus[index] == nil then
        return false
    end
    table.remove(shot.focus, index)
    touch(shot)
    return true
end

-- Posun bodu zájmu v čase; nepřeskočí sousedy.
function S.moveFocusTime(shot, index, t)
    local f = shot.focus[index]
    if f == nil then
        return nil
    end
    local lo = index > 1 and shot.focus[index - 1].t + S.MIN_GAP or 0
    local hi = index < #shot.focus and shot.focus[index + 1].t - S.MIN_GAP or math.huge
    if lo > hi then
        return f.t
    end
    f.t = M.clamp(t, lo, hi)
    touch(shot)
    return f.t
end

-- Trvalé číslo herce v záběru (přežije uložení i přeskládání řádků); kopie herce (stejné číslo jako některý dřív
-- v seznamu) dostane nové.
function S.actorId(shot, actor)
    local top, clash, before = 0, false, true
    for _, a in ipairs(shot.actors) do
        if a == actor then
            before = false
        else
            top = math.max(top, a.id or 0)
            clash = clash or (before and actor.id ~= nil and a.id == actor.id)
        end
    end
    if actor.id == nil or clash then
        actor.id = top + 1
    end
    return actor.id
end

function S.actorById(shot, id)
    for i, a in ipairs(shot.actors) do
        if a.id == id then
            return a, i
        end
    end
    return nil
end

-- Cíl bodu zájmu pro postavu herce (vozidla mají cílem své uniqueId).
S.PERSON_TARGET = "person:"

function S.personTarget(shot, actor)
    return S.PERSON_TARGET .. S.actorId(shot, actor)
end

function S.personOfTarget(shot, target)
    local id = type(target) == "string" and tonumber(target:match("^" .. S.PERSON_TARGET .. "(%d+)$")) or nil
    return id ~= nil and S.actorById(shot, id) or nil
end

-- Bod zájmu, který platí v čase t (jeho úsek trvá do dalšího), nebo nil před prvním.
function S.focusIndexAt(shot, t)
    local index
    for i, f in ipairs(shot.focus) do
        if f.t <= t + 1e-9 then
            index = i
        end
    end
    return index
end

-- Rozdělí úsek bodu zájmu v čase t: druhá část míří na totéž bez přechodu (with = nil), nebo od t jinam (with = uid,
-- false = volný pohled). Vrací index nového bodu, nebo nil, když v t žádný úsek nezačíná dřív.
function S.splitFocus(shot, t, with)
    local i = S.focusIndexAt(shot, t)
    local f = i ~= nil and shot.focus[i] or nil
    if f == nil or t - f.t < S.MIN_GAP or (shot.focus[i + 1] ~= nil and shot.focus[i + 1].t - t < S.MIN_GAP) then
        return nil
    end
    local target = f.target
    if with == false then
        target = nil
    elseif with ~= nil then
        target = with
    end
    local index = S.setFocus(shot, t, target, f.height)
    shot.focus[index].blend = with == nil and 0 or f.blend
    touch(shot)
    return index
end

-- Začátek prvního bloku záběru (0 bez bloků).
function S.firstStart(shot)
    local first = math.huge
    for _, seg in ipairs(shot.segments) do
        first = math.min(first, seg.t)
    end
    return first < math.huge and first or 0
end

-- Stav míření v čase t: předchozí a aktuální bod zájmu (nil = volně) a průběh přechodu mezi nimi 0..1.
function S.focusAt(shot, t)
    local current, index = nil, nil
    for i, f in ipairs(shot.focus) do
        if f.t <= t + 1e-9 then
            current, index = f, i
        else
            break
        end
    end
    if current == nil then
        return nil, nil, 1
    end
    local blend = current.blend or S.FOCUS_BLEND
    -- bod zájmu od začátku záběru míří hned: není z čeho přecházet (přechod z vlastního pohledu = bod zájmu později)
    if index == 1 and current.t <= S.firstStart(shot) + S.KEY_SNAP then
        blend = 0
    end
    local u = blend > 1e-6 and M.smoothstep(M.clamp((t - current.t) / blend, 0, 1)) or 1
    return shot.focus[index - 1], current, u
end

---------------------------------------------------------------------------------------------------
-- třes „z ruky": deterministický v čase (stejné přehrání = stejný obraz), součet nesoudělných sinusovek

S.SHAKE_ANGLE = math.rad(0.35)
S.SHAKE_POS = 0.025

function S.shakeOffset(level, t)
    if level == nil or level <= 0 then
        return 0, 0, 0, 0, 0
    end
    local function wave(a, b, c, phase)
        return (math.sin(t * a + phase) + 0.6 * math.sin(t * b + phase * 1.7) + 0.35 * math.sin(t * c + phase * 2.3)) / 1.95
    end
    local yaw = wave(1.3, 2.9, 6.1, 0.4) * S.SHAKE_ANGLE * level
    local pitch = wave(1.7, 3.3, 7.3, 1.9) * S.SHAKE_ANGLE * level
    local dx = wave(0.9, 2.3, 5.3, 2.7) * S.SHAKE_POS * level
    local dy = wave(1.1, 2.7, 4.9, 3.6) * S.SHAKE_POS * level
    local dz = wave(0.7, 2.1, 5.9, 4.4) * S.SHAKE_POS * level
    return yaw, pitch, dx, dy, dz
end
