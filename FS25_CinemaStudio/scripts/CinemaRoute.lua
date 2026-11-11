-- Trasa vozidla: naklikané body vyhlazené do husté lomené čáry (po ~1 m) a řízení po ní metodou pure pursuit:
-- vozidlo míří na bod kus před sebou na trase, rychlost tempomatu se sníží před ostrou zatáčkou a před koncem.
-- Bez herních API (výšky se neřeší, trasa je 2D).

CinemaRoute = CinemaRoute or {}
local R = CinemaRoute
local M = CinemaMath

R.SPACING = 1.0
R.CURVE_LOOK = 14 -- m; jak daleko dopředu se hledá zatáčka
R.MIN_KMH = 3
R.WALK_MIN_KMH = 0.5 -- postava smí jít pomaleji než vozidlo jet
R.DECEL = 1.2 -- m/s²; brzdění před koncem trasy
R.ACCEL = 1.5 -- m/s²; rozjezd ze startu a z pauzy
R.ARRIVE = 1.5 -- m
R.TURN_DEADBAND = math.rad(8)

R.TIME_FACTOR = 1.1 -- rozjezd a dojezd zhruba prodlouží jízdu o 10 %
R.DEFAULT_KMH = 15
R.STOP_DEFAULT = 1 -- s; nejkratší zastávka v bodě s rychlostí 0 km/h
R.CUSP_WAIT = 1 -- s; vozidlo stojí v bodě, kde se mění směr jízdy (vpřed / couvání)
R.REVERSE_KMH = 15 -- nejvyšší rychlost při couvání
R.WALK_ACCEL = 12 -- m/s²; postava se rozejde i zastaví skoro hned jako hráč (ten zrychluje okamžitě) a v zatáčkách nezpomaluje (route.walk)

-- points = { {x, z, kmh?, wait?, reverse?}, ... }; kmh bodu přebíjí rychlost celé trasy defaultKmh, wait je pauza v bodě
-- v sekundách (vozidlo tam zastaví a po ní pokračuje), reverse znamená, že úsek k tomuto bodu vozidlo couvá (zádí napřed).
-- Vrací nil, když bodů není dost.
-- route.ctrlS[i], route.ctrlKmh[i] a route.ctrlWait[i] nesou vzdálenost po trase, rychlost a pauzu v naklikaných bodech.
-- route.revTo[j] říká, jestli se úsek vrcholů j - 1 → j couvá; route.cusps jsou body se změnou směru (vozidlo tam stojí)
-- jako { s, dur, cusp = true } a route.hasReverse, jestli se někde couvá. Trasa se v bodě změny směru nevyhlazuje.
function R.build(points, defaultKmh)
    if points == nil or #points < 2 then
        return nil
    end
    local pts = {}
    for i, p in ipairs(points) do
        pts[i] = { p[1], 0, p[2] }
    end
    local function revSeg(i)
        return points[i + 1][5] == true
    end
    local route = { xs = {}, zs = {}, ss = {}, ctrlS = {}, ctrlKmh = {}, ctrlWait = {}, ctrlCusp = {}, revTo = {}, cusps = {} }
    local function push(x, z, rev)
        local n = #route.xs
        local s = 0
        if n > 0 then
            local dx, dz = x - route.xs[n], z - route.zs[n]
            local d = math.sqrt(dx * dx + dz * dz)
            if d < 1e-3 then
                return
            end
            s = route.ss[n] + d
        end
        route.xs[n + 1], route.zs[n + 1], route.ss[n + 1] = x, z, s
        route.revTo[n + 1] = rev
    end
    for i = 1, #pts - 1 do
        local p1, p2 = pts[i], pts[i + 1]
        local cuspStart = i > 1 and revSeg(i - 1) ~= revSeg(i)
        local cuspEnd = i + 1 < #pts and revSeg(i) ~= revSeg(i + 1)
        local p0 = (i > 1 and not cuspStart and pts[i - 1]) or { 2 * p1[1] - p2[1], 0, 2 * p1[3] - p2[3] }
        local p3 = (i + 2 <= #pts and not cuspEnd and pts[i + 2]) or { 2 * p2[1] - p1[1], 0, 2 * p2[3] - p1[3] }
        local dx, dz = p2[1] - p1[1], p2[3] - p1[3]
        local count = math.max(1, math.ceil(math.sqrt(dx * dx + dz * dz) / R.SPACING))
        for k = 0, count - 1 do
            local p = M.catmullRom(p0, p1, p2, p3, k / count)
            local rev = revSeg(i)
            if k == 0 and i > 1 then
                rev = revSeg(i - 1)
            end
            push(p[1], p[3], rev)
            if k == 0 then
                route.ctrlS[i] = route.ss[#route.ss]
            end
        end
    end
    local last = pts[#pts]
    push(last[1], last[3], revSeg(#pts - 1))
    route.length = route.ss[#route.ss]
    route.ctrlS[#pts] = route.length
    for i, p in ipairs(points) do
        route.ctrlKmh[i] = p[3] or defaultKmh or R.DEFAULT_KMH
        -- 0 km/h v bodě = zastávka; bez čekání stojí aspoň STOP_DEFAULT
        route.ctrlWait[i] = p[4] or ((p[3] == 0 and i > 1 and i < #points) and R.STOP_DEFAULT or 0)
        if i > 1 and i < #points and revSeg(i - 1) ~= revSeg(i) then
            route.ctrlCusp[i] = true
            route.ctrlWait[i] = math.max(route.ctrlWait[i], R.CUSP_WAIT)
        end
    end
    route.hasReverse = false
    for i = 2, #pts do
        route.hasReverse = route.hasReverse or revSeg(i - 1)
    end
    if #route.xs < 2 then
        return nil
    end
    for i = 2, #pts - 1 do
        if route.ctrlCusp[i] then
            route.cusps[#route.cusps + 1] = { s = route.ctrlS[i], dur = route.ctrlWait[i], cusp = true }
        end
    end
    return route
end

local function segmentIndex(route, s)
    local n = #route.xs
    return s <= 0 and 1 or (s >= route.length and n - 1 or M.findSegment(route.ss, s))
end

-- Couvá se v místě s trasy (na úseku, který začíná v s nebo za ním)?
function R.reverseAt(route, s)
    return route.revTo[segmentIndex(route, s) + 1] == true
end

function R.pointAt(route, s)
    local n = #route.xs
    if s <= 0 then
        return route.xs[1], route.zs[1]
    end
    if s >= route.length then
        return route.xs[n], route.zs[n]
    end
    local i = M.findSegment(route.ss, s)
    local u = (s - route.ss[i]) / (route.ss[i + 1] - route.ss[i])
    return route.xs[i] + (route.xs[i + 1] - route.xs[i]) * u, route.zs[i] + (route.zs[i + 1] - route.zs[i]) * u
end

-- Směr trasy (úhel jako yaw: atan2(dx, dz)) ve vzdálenosti s.
function R.headingAt(route, s)
    local i = segmentIndex(route, s)
    return math.atan2(route.xs[i + 1] - route.xs[i], route.zs[i + 1] - route.zs[i])
end

-- Natočení vozidla v místě s: při couvání zádí napřed, tedy opačně než směr trasy. V bodě změny směru na sebe navazuje.
function R.bodyHeadingAt(route, s)
    local h = R.headingAt(route, s)
    return R.reverseAt(route, s) and h + math.pi or h
end

-- Nejbližší místo na trase k (x, z). Hledá se v okně kolem hintS (vozidlo nejede pozpátku), bez něj celá trasa; floorS a ceilS
-- hledání omezí na úsek mezi dvěma místy (úseky před a za bodem změny směru leží na sobě, nesmí se zaměnit).
function R.project(route, x, z, hintS, window, floorS, ceilS)
    local n = #route.xs
    local lo, hi = floorS or 0, ceilS or route.length
    if hintS ~= nil then
        window = window or 25
        lo, hi = math.max(lo, hintS - 5), math.min(hi, hintS + window)
    end
    local first = math.max(1, M.findSegment(route.ss, lo))
    local last = math.min(n - 1, M.findSegment(route.ss, math.max(hi - 1e-6, lo)))
    if last < first then
        last = first
    end
    local bestS, bestD = 0, math.huge
    for i = first, last do
        local ax, az = route.xs[i], route.zs[i]
        local bx, bz = route.xs[i + 1], route.zs[i + 1]
        local vx, vz = bx - ax, bz - az
        local len2 = vx * vx + vz * vz
        local u = len2 > 0 and M.clamp(((x - ax) * vx + (z - az) * vz) / len2, 0, 1) or 0
        local px, pz = ax + vx * u, az + vz * u
        local d = (x - px) ^ 2 + (z - pz) ^ 2
        if d < bestD then
            bestD = d
            bestS = route.ss[i] + u * math.sqrt(len2)
        end
    end
    return bestS, math.sqrt(bestD)
end

R.LOOK_TURN_GAIN = 1.5 -- jak silně zatáčka před vozidlem zkrátí dohled
R.LOOK_MIN_CURVE = 2.5 -- m; nejkratší dohled v ostré zatáčce

-- Jak daleko před vozidlem leží bod, na který řídí (m) — s rychlostí roste, aby jízda nekmitala; turn (rad, změna směru
-- na úseku dohledu) ho zkrátí, aby vozidlo v zatáčce neřezalo roh (u zdi nebo ve dvoře by do ní najelo).
function R.lookahead(kmh, turn)
    local look = M.clamp(4 + kmh / 3.6 * 0.8, 4, 14)
    if turn ~= nil and turn > 0 then
        look = math.max(look / (1 + turn * R.LOOK_TURN_GAIN), math.min(R.LOOK_MIN_CURVE, look))
    end
    return look
end

-- Největší změna směru na úseku [s, s + dist] (rad).
function R.turnAhead(route, s, dist)
    local h0 = R.headingAt(route, s)
    local worst = 0
    local step = 2
    local d = step
    while d <= dist do
        if s + d > route.length then
            break
        end
        worst = math.max(worst, math.abs(M.angleDiff(h0, R.headingAt(route, s + d))))
        d = d + step
    end
    return worst
end

-- Vzdálenost po trase, kde vozidlo naposledy stálo (start nebo pauza v bodě) před místem s.
function R.lastStopS(route, s)
    local last = 0
    for i = 2, #route.ctrlS - 1 do
        if route.ctrlWait[i] > 0 and route.ctrlS[i] <= s + 1e-6 then
            last = route.ctrlS[i]
        end
    end
    return last
end

-- Nejbližší pauza v bodě za místem s, nebo nil.
function R.nextStopS(route, s)
    for i = 2, #route.ctrlS - 1 do
        if route.ctrlWait[i] > 0 and route.ctrlS[i] > s + 1e-6 then
            return route.ctrlS[i]
        end
    end
    return nil
end

-- Rychlost (km/h), na kterou se má vozidlo v místě s omezit; stopS je místo, kde má zastavit (pauza), jinak konec trasy.
-- Za startem a za pauzou se rychlost zvedá plynule (R.ACCEL), před zastavením klesá (R.DECEL).
function R.targetSpeed(route, s, cruiseKmh, stopS)
    local remaining = (stopS or route.length) - s
    -- postava dojde až do bodu; R.ARRIVE platí jen pro vozidlo (řízení ho zastaví před bodem), u chůze by poslední
    -- metr a půl lezla nejnižší rychlostí
    if route.walk then
        local braking = math.sqrt(2 * R.WALK_ACCEL * math.max(remaining, 0)) * 3.6
        local launch = math.sqrt(2 * R.WALK_ACCEL * math.max(s - R.lastStopS(route, s), 0)) * 3.6
        return math.max(math.min(cruiseKmh, braking, launch), math.min(R.MIN_KMH, cruiseKmh))
    end
    if remaining <= R.ARRIVE then
        return 0
    end
    -- mírné oblouky (do TURN_DEADBAND) se jedou plnou rychlostí, jinak by vyhlazení trasy brzdilo i na rovině
    local turn = math.max(R.turnAhead(route, s, R.CURVE_LOOK) - R.TURN_DEADBAND, 0)
    local factor = M.clamp(1 - turn / (math.pi * 0.5) * 0.8, 0.3, 1)
    local braking = math.sqrt(2 * R.DECEL * math.max(remaining - R.ARRIVE, 0)) * 3.6
    local launch = math.sqrt(2 * R.ACCEL * math.max(s - R.lastStopS(route, s), 0)) * 3.6
    return math.max(math.min(cruiseKmh * factor, braking, launch), math.min(R.MIN_KMH, cruiseKmh))
end

-- Rychlost tempomatu (km/h) v místě s: mezi naklikanými body se rychlost plynule mění; postava (route.walk) jde celý úsek
-- rychlostí jeho prvního bodu a v dalším bodě ji přepne natvrdo.
function R.cruiseAt(route, s)
    local n = #route.ctrlS
    local kmh = route.ctrlKmh[n]
    if s <= route.ctrlS[1] then
        kmh = route.ctrlKmh[1]
    else
        for i = 1, n - 1 do
            local a, b = route.ctrlS[i], route.ctrlS[i + 1]
            if s < b then
                local span = b - a
                local u = span > 1e-6 and (s - a) / span or 1
                kmh = route.walk and route.ctrlKmh[i] or route.ctrlKmh[i] + (route.ctrlKmh[i + 1] - route.ctrlKmh[i]) * u
                break
            end
        end
    end
    return R.reverseAt(route, s) and math.min(kmh, R.REVERSE_KMH) or kmh
end

-- Index naklikaného bodu, za který patří nový bod ve vzdálenosti s (vkládá se mezi i a i + 1), nebo nil,
-- když je s u existujícího bodu blíž než minGap.
function R.insertIndex(route, s, minGap)
    local n = #route.ctrlS
    for i = 1, n do
        if math.abs(route.ctrlS[i] - s) < minGap then
            return nil
        end
    end
    for i = 1, n - 1 do
        if s > route.ctrlS[i] and s < route.ctrlS[i + 1] then
            return i
        end
    end
    return nil
end

local plans = setmetatable({}, { __mode = "k" })

-- Otisk vstupů plánu: ploché pole čísel a příznaků. Plán se ptá několik set krát za snímek (dráha kamery na vozidle ho
-- vzorkuje po bodech), proto se otisk jen porovnává s uloženým (signatureMatches), nestaví se z textu.
local function signature(actor)
    local sig = { actor.speed or R.DEFAULT_KMH }
    local n = 1
    local curve = actor.curves ~= nil and actor.curves.speed or nil
    if CinemaChannels.hasPoints(curve) then
        for _, p in ipairs(curve.points) do
            sig[n + 1], sig[n + 2], sig[n + 3] = p.t, p.v, p.mode or "linear"
            n = n + 3
        end
    end
    sig[n + 1] = "|"
    n = n + 1
    for _, p in ipairs(actor.points or {}) do
        sig[n + 1], sig[n + 2], sig[n + 3], sig[n + 4], sig[n + 5], sig[n + 6] = p[1], p[2], p[3] or false, p[4] or false, p[5] and true or false,
            p[7] and true or false
        n = n + 6
    end
    return sig
end

local function signatureMatches(actor, sig)
    if sig[1] ~= (actor.speed or R.DEFAULT_KMH) then
        return false
    end
    local n = 1
    local curve = actor.curves ~= nil and actor.curves.speed or nil
    if CinemaChannels.hasPoints(curve) then
        for _, p in ipairs(curve.points) do
            if sig[n + 1] ~= p.t or sig[n + 2] ~= p.v or sig[n + 3] ~= (p.mode or "linear") then
                return false
            end
            n = n + 3
        end
    end
    if sig[n + 1] ~= "|" then
        return false
    end
    n = n + 1
    for _, p in ipairs(actor.points or {}) do
        if sig[n + 1] ~= p[1] or sig[n + 2] ~= p[2] or sig[n + 3] ~= (p[3] or false) or sig[n + 4] ~= (p[4] or false)
            or sig[n + 5] ~= (p[5] and true or false) or sig[n + 6] ~= (p[7] and true or false) then
            return false
        end
        n = n + 6
    end
    return sig[n + 1] == nil
end

-- Trasa herce s časovou tabulkou: times[i] = za jak dlouho od startu jízdy (bez pauz) vozidlo dojede do i-tého vrcholu
-- trasy; pauzy v bodech jsou zvlášť v plan.pauses = { {s, dur}, … } (podle s) a plan.total je celá doba i s nimi.
-- Počítá se z rychlosti tempomatu, zpomalení v zatáčkách a dojezdu; přepočítá se jen po změně bodů nebo rychlosti.
-- Plán jízdy podle křivky rychlosti v čase (km/h od startu jízdy): rychlost se integruje po trase. Křivka platí jen mezi
-- svým prvním a posledním bodem; před ním jede vozidlo podle bodů trasy (tempomat, rozjezd), za ním taky, ledaže křivka
-- končí nulou: pak vozidlo stojí. Pauzy v bodech trasy se v plánu s křivkou nepoužívají (zastavení je nulová rychlost v křivce).
local CURVE_STEP = 0.05 -- s
local CURVE_LIMIT = 7200 -- s; pojistka proti nekonečné smyčce

-- Rychlost (km/h) podle bodů trasy v místě s, bez pauz.
function R.baseSpeed(route, s)
    return math.max(R.targetSpeed(route, s, R.cruiseAt(route, s), nil), route.walk and R.WALK_MIN_KMH or R.MIN_KMH)
end

-- Křivka končí nulou a čas t (od startu jízdy) je za jejím koncem: vozidlo stojí.
function R.curveStopped(curve, t)
    local pts = curve ~= nil and curve.points or nil
    local last = pts ~= nil and pts[#pts] or nil
    return last ~= nil and last.v <= 0 and t > last.t + 1e-9
end

local function planFromCurve(route, curve)
    local ss = route.ss
    local n = #ss
    local times = { 0 }
    local sampled = { 0 } -- vzdálenost po trase po krocích CURVE_STEP (přesný průběh, i když vozidlo stojí uvnitř úseku trasy)
    local s, t, i = 0, 0, 1
    local holds, h = route.cusps, 1
    while i < n and t < CURVE_LIMIT do
        local cusp = holds[h]
        if R.curveStopped(curve, t) then
            break
        elseif cusp ~= nil and s >= cusp.s - 1e-6 then
            for _ = 1, math.ceil(cusp.dur / CURVE_STEP) do
                t = t + CURVE_STEP
                sampled[#sampled + 1] = math.min(s, route.length)
            end
            h = h + 1
        else
            local mid = t + CURVE_STEP * 0.5
            local kmh
            if CinemaChannels.isActive(curve, mid) then
                kmh = math.max(CinemaChannels.valueAt(curve, mid) or 0, 0)
            else
                kmh = R.baseSpeed(route, s)
            end
            if R.reverseAt(route, s) then
                kmh = math.min(kmh, R.REVERSE_KMH)
            end
            local nextS = s + kmh / 3.6 * CURVE_STEP
            if cusp ~= nil and nextS > cusp.s then
                nextS = cusp.s
            end
            while i < n and ss[i + 1] <= nextS + 1e-9 do
                local span = nextS - s
                local u = span > 1e-9 and (ss[i + 1] - s) / span or 1
                times[i + 1] = t + CURVE_STEP * M.clamp(u, 0, 1)
                i = i + 1
            end
            s, t = nextS, t + CURVE_STEP
            sampled[#sampled + 1] = math.min(s, route.length)
        end
    end
    local plan = { route = route, times = times, pauses = {}, holds = route.cusps, curve = curve, sampled = sampled, reached = i >= n }
    if i >= n then
        plan.total = times[n]
    else
        plan.total = t
        for k = i + 1, n do
            times[k] = t + 1e6 + k
        end
    end
    return plan
end

local FIT_MAX = 600 -- s; nejdelší dojezd, na který se poslední bod křivky natáhne

-- Krajní body křivky rychlosti jsou napevno: první v čase 0, poslední je nula přesně v okamžiku dojezdu na konec trasy.
-- Čas posledního bodu se proto posune tak, aby vozidlo dojelo na konec právě, když rychlost klesne na nulu. Dojede-li
-- vozidlo na konec ještě před předposledním bodem, rychlost tam skokově padne na nulu a body zůstanou, kde jsou. Když
-- křivka zastaví vozidlo dřív (dvě nuly na konci) nebo nedojede ani s nejdelším dojezdem, poslední bod taky zůstane.
-- Indexy bodů křivky rychlosti, kam vozidlo nedojede, protože je už na konci trasy (vyšší rychlost = trasa ujetá dřív);
-- krajní body se nepočítají.
function R.deadCurvePoints(actor)
    local curve = actor.curves ~= nil and actor.curves.speed or nil
    local plan = CinemaChannels.hasPoints(curve) and R.plan(actor) or nil
    local out = {}
    if plan == nil or not plan.reached then
        return out
    end
    local pts = curve.points
    for i = 2, #pts - 1 do
        if pts[i].t >= plan.total - CinemaChannels.MIN_GAP then
            out[#out + 1] = i
        end
    end
    return out
end

-- Smaže body za koncem jízdy; konec křivky se pak znovu napasuje (R.fitCurveEnd), takže vozidlo do konce trasy
-- plynule zpomalí místo skokového zastavení. Vrací počet smazaných bodů.
function R.trimCurve(actor)
    local dead = R.deadCurvePoints(actor)
    for k = #dead, 1, -1 do
        table.remove(actor.curves.speed.points, dead[k])
    end
    return #dead
end

function R.fitCurveEnd(route, curve)
    local pts = curve.points
    if #pts < 2 then
        return
    end
    pts[1].t = 0
    pts[#pts].v = 0
    local gap = CinemaChannels.MIN_GAP
    local n = #pts
    local last, prev = pts[n], pts[n - 1]
    if n >= 3 then
        local keep = last.t
        last.t = prev.t + gap
        local early = planFromCurve(route, curve)
        last.t = math.max(keep, prev.t + gap)
        if early.reached and early.total <= prev.t + 1e-6 then
            return
        end
    end
    if prev.v <= 0 then
        return
    end
    local original = last.t
    local function arrives(t)
        last.t = t
        return planFromCurve(route, curve).reached
    end
    local lo = pts[n - 1].t + gap
    local hi = lo + FIT_MAX
    if arrives(lo) then
        last.t = lo
        return
    end
    if not arrives(hi) then
        last.t = original
        return
    end
    while hi - lo > 0.005 do
        local mid = (lo + hi) * 0.5
        if arrives(mid) then
            hi = mid
        else
            lo = mid
        end
    end
    last.t = math.ceil(hi * 100) / 100
end

-- Při kreslení editoru (R.frozen) se body herců nemění, takže plán se nekontroluje proti otisku při každém z tisíců dotazů.
R.frozen = false

function R.plan(actor)
    local cached = plans[actor]
    if cached ~= nil and (R.frozen or signatureMatches(actor, cached.sig)) then
        return cached.plan
    end
    -- bod s p[7] (výstup postavy z vozidla) začíná další část trasy; plán herce je jen první část
    local points = actor.points
    for j = 2, #(points or {}) do
        if points[j][7] then
            points = { unpack(points, 1, j - 1) }
            break
        end
    end
    local route = R.build(points, actor.speed)
    if route ~= nil then
        route.walk = actor.person ~= nil or actor.walk == true
    end
    local plan = nil
    local curve = actor.curves ~= nil and actor.curves.speed or nil
    if route ~= nil and CinemaChannels.hasPoints(curve) then
        R.fitCurveEnd(route, curve)
        plan = planFromCurve(route, curve)
    elseif route ~= nil then
        local times = { 0 }
        local t = 0
        for i = 1, #route.xs - 1 do
            local mid = (route.ss[i] + route.ss[i + 1]) * 0.5
            local kmh = math.max(R.targetSpeed(route, mid, R.cruiseAt(route, mid), R.nextStopS(route, mid)), route.walk and R.WALK_MIN_KMH or R.MIN_KMH)
            t = t + (route.ss[i + 1] - route.ss[i]) / (kmh / 3.6) * (route.walk and 1 or R.TIME_FACTOR)
            times[i + 1] = t
        end
        local pauses = {}
        for i = 2, #route.ctrlS - 1 do
            if route.ctrlWait[i] > 0 then
                pauses[#pauses + 1] = { s = route.ctrlS[i], dur = route.ctrlWait[i], cusp = route.ctrlCusp[i] }
                t = t + route.ctrlWait[i]
            end
        end
        plan = { route = route, times = times, pauses = pauses, holds = route.cusps, total = t }
    end
    plans[actor] = { sig = signature(actor), plan = plan }
    return plan
end

-- Čas jízdy bez pauz do místa s.
local function movingTimeAtS(plan, s)
    local route = plan.route
    if s <= 0 then
        return 0
    end
    local i = M.findSegment(route.ss, math.min(s, route.length))
    local span = route.ss[i + 1] - route.ss[i]
    local u = span > 1e-9 and M.clamp((s - route.ss[i]) / span, 0, 1) or 0
    return plan.times[i] + (plan.times[i + 1] - plan.times[i]) * u
end

R.STAND_SNAP = 1 -- m; vozidlo, které podle křivky zastaví tak blízko před bodem, v bodě stojí (čas bodu = příjezd)
R.STAND_MIN = 0.5 -- s; jak dlouho musí stát, aby to bylo zastavení

-- Křivkou zastavené vozidlo kousek před místem s: čas, kdy tam dojelo, jinak nil. Bez toho by bod, u kterého vozidlo stojí,
-- na ose přeskakoval mezi příjezdem a rozjezdem podle toho, jestli zastaví centimetr před ním, nebo za ním.
local function standingArrival(plan, s)
    local sampled = plan.sampled
    local steps = math.ceil(R.STAND_MIN / CURVE_STEP)
    for k = 1, #sampled do
        if sampled[k] >= s - 1e-6 then
            return nil
        elseif sampled[k] >= s - R.STAND_SNAP then
            local last = math.min(k + steps, #sampled)
            if last - k >= steps and sampled[last] - sampled[k] < 0.02 then
                return (k - 1) * CURVE_STEP
            end
        end
    end
    return nil
end

-- Za jak dlouho od startu jízdy vozidlo dojede do místa ve vzdálenosti s po trase (do bodu s pauzou dojede před ní).
local TIME_CACHE_MAX = 512

-- Výsledek se pamatuje u plánu (ten se při změně bodů nebo rychlosti nahradí novým): osa ptá na čas stejných bodů trasy
-- několik tisíckrát za sekundu.
function R.timeAtS(plan, s)
    local cache = plan.timeCache
    if cache == nil or plan.timeCacheN >= TIME_CACHE_MAX then
        cache, plan.timeCache, plan.timeCacheN = {}, {}, 0
        cache = plan.timeCache
    end
    local known = cache[s]
    if known ~= nil then
        return known
    end
    local t = R.computeTimeAtS(plan, s)
    cache[s] = t
    plan.timeCacheN = plan.timeCacheN + 1
    return t
end

function R.computeTimeAtS(plan, s)
    local route = plan.route
    if s <= 0 then
        return 0
    elseif s >= route.length then
        return plan.total
    end
    if plan.sampled ~= nil then
        local arrival = standingArrival(plan, s)
        if arrival ~= nil then
            return arrival
        end
    end
    local t = movingTimeAtS(plan, s)
    for _, p in ipairs(plan.pauses) do
        if p.s < s - 1e-6 then
            t = t + p.dur
        end
    end
    return t
end

-- Kde má být vozidlo za t sekund od startu jízdy: x, z, vzdálenost po trase, směr. V pauze stojí v jejím bodě.
function R.positionAtTime(plan, t)
    local route = plan.route
    local s
    if plan.sampled ~= nil then
        local u = math.max(t, 0) / CURVE_STEP
        local k = math.floor(u) + 1
        if k >= #plan.sampled then
            s = plan.sampled[#plan.sampled]
        else
            s = plan.sampled[k] + (plan.sampled[k + 1] - plan.sampled[k]) * (u - math.floor(u))
        end
    elseif t <= 0 then
        s = 0
    elseif t >= plan.total then
        s = route.length
    else
        local shift, held = 0, nil
        for _, p in ipairs(plan.pauses) do
            local arrival = movingTimeAtS(plan, p.s) + shift
            if t < arrival then
                break
            elseif t < arrival + p.dur then
                held = p.s
                break
            end
            shift = shift + p.dur
        end
        if held ~= nil then
            s = held
        else
            local moving = t - shift
            local i = M.findSegment(plan.times, moving)
            local span = plan.times[i + 1] - plan.times[i]
            local u = span > 1e-9 and M.clamp((moving - plan.times[i]) / span, 0, 1) or 0
            s = route.ss[i] + (route.ss[i + 1] - route.ss[i]) * u
        end
    end
    local x, z = R.pointAt(route, s)
    return x, z, s, R.bodyHeadingAt(route, s)
end
