-- Kanály: průběh jedné hodnoty v čase z ovládacích bodů (rychlost vozidla, zoom kamery, osa ramene…).
-- Kanál = { points = { { t, v, mode } … } seřazené podle t, hidden }. mode bodu určuje, jak se hodnota mění od něj k dalšímu
-- bodu: "linear" = úsečka, "step" = skok (drží se hodnota bodu až do dalšího), "smooth" = hladká křivka bez překmitů.
-- Před prvním a za posledním bodem platí hodnota krajního bodu. Bez herních API.

CinemaChannels = CinemaChannels or {}
local Ch = CinemaChannels

Ch.MODES = { "linear", "step", "smooth" }
Ch.MIN_GAP = 0.1 -- s; nejmenší odstup bodů v čase

function Ch.new()
    return { points = {} }
end

function Ch.hasPoints(ch)
    return ch ~= nil and ch.points ~= nil and #ch.points > 0
end

-- Strmost hladké křivky v bodě k: harmonický průměr sousedních sklonů (nepřekmitne), na krajích sklon sousedního úseku.
local function slope(pts, k)
    local n = #pts
    local function secant(i)
        local dt = pts[i + 1].t - pts[i].t
        return dt > 1e-9 and (pts[i + 1].v - pts[i].v) / dt or 0
    end
    if n < 2 then
        return 0
    end
    if k == 1 then
        return secant(1)
    elseif k == n then
        return secant(n - 1)
    end
    local d1, d2 = secant(k - 1), secant(k)
    if d1 * d2 <= 0 then
        return 0
    end
    return 2 * d1 * d2 / (d1 + d2)
end

-- Hodnota v čase t; nil, když kanál nemá žádné body.
function Ch.valueAt(ch, t)
    local pts = ch ~= nil and ch.points or nil
    local n = pts ~= nil and #pts or 0
    if n == 0 then
        return nil
    end
    if t <= pts[1].t then
        return pts[1].v
    end
    if t >= pts[n].t then
        return pts[n].v
    end
    local i = 1
    while pts[i + 1].t <= t do
        i = i + 1
    end
    local a, b = pts[i], pts[i + 1]
    local mode = a.mode or "linear"
    if mode == "step" then
        return a.v
    end
    local h = b.t - a.t
    local u = (t - a.t) / h
    if mode == "linear" then
        return a.v + (b.v - a.v) * u
    end
    local m0, m1 = slope(pts, i), slope(pts, i + 1)
    local u2, u3 = u * u, u * u * u
    return (2 * u3 - 3 * u2 + 1) * a.v + (u3 - 2 * u2 + u) * h * m0 + (-2 * u3 + 3 * u2) * b.v + (u3 - u2) * h * m1
end

-- Platí kanál v čase t? Jen mezi prvním a posledním bodem; před ním a za ním do věci nezasahuje.
function Ch.isActive(ch, t)
    return Ch.hasPoints(ch) and t >= ch.points[1].t - 1e-9 and t <= ch.points[#ch.points].t + 1e-9
end

-- Přidá bod; je-li v dosahu MIN_GAP jiný, jen mu změní hodnotu. Vrací index a true, když vznikl nový.
function Ch.addPoint(ch, t, v, mode)
    t = math.max(t, 0)
    for i, p in ipairs(ch.points) do
        if math.abs(p.t - t) < Ch.MIN_GAP then
            p.v = v
            return i, false
        end
    end
    local index = #ch.points + 1
    for i, p in ipairs(ch.points) do
        if p.t > t then
            index = i
            break
        end
    end
    table.insert(ch.points, index, { t = t, v = v, mode = mode or "smooth" })
    return index, true
end

function Ch.removePoint(ch, index)
    if ch.points[index] ~= nil then
        table.remove(ch.points, index)
    end
end

-- Posune bod v čase i na hodnotu (nepředběhne sousedy). Vrací nový index (pořadí se nemění).
function Ch.movePoint(ch, index, t, v)
    local p = ch.points[index]
    if p == nil then
        return nil
    end
    local lo = index > 1 and ch.points[index - 1].t + Ch.MIN_GAP or 0
    local hi = index < #ch.points and ch.points[index + 1].t - Ch.MIN_GAP or math.huge
    p.t = math.min(math.max(t, lo), math.max(lo, hi))
    p.v = v
    return index
end

Ch.STOP_DECEL = 2.5 -- m/s²; brzdění vloženého zastavení
Ch.STOP_ACCEL = 2 -- m/s²; rozjezd po něm
Ch.STOP_HOLD = 2 -- s; výchozí délka stání

-- Zastavení v rychlosti v čase t: zabrzdí na nulu v t, stojí hold sekund a rozjede se zpět na rychlost, kterou mělo.
-- Body od začátku brzdění dál se posunou o vložený čas, takže jízda po rozjezdu je stejná, jen později. Vrací ten posun,
-- false, když v t skoro stojí.
function Ch.insertStop(ch, t, hold)
    local v = Ch.valueAt(ch, t) or 0
    if v <= 0.5 then
        return false
    end
    local ts = math.max(t - v / 3.6 / Ch.STOP_DECEL, 0)
    local launch = v / 3.6 / Ch.STOP_ACCEL
    local shift = (t - ts) + hold + launch
    for _, p in ipairs(ch.points) do
        if p.t >= ts - 1e-9 then
            p.t = p.t + shift
        end
    end
    Ch.addPoint(ch, ts, v)
    Ch.addPoint(ch, t, 0)
    Ch.addPoint(ch, t + hold, 0)
    Ch.addPoint(ch, t + hold + launch, v)
    return shift
end

-- Je bod index koncem stání (nula po nule, ne poslední bod)? Jeho tažení posouvá i všechno za ním.
function Ch.isStopEnd(ch, index)
    local p, prev = ch.points[index], ch.points[index - 1]
    return p ~= nil and prev ~= nil and index < #ch.points and p.v <= 0.01 and prev.v <= 0.01
end

-- Posune bod index a všechny za ním o dt (ne před předchozí bod).
function Ch.shiftFrom(ch, index, dt)
    local prev = ch.points[index - 1]
    if prev ~= nil then
        dt = math.max(dt, prev.t + Ch.MIN_GAP - ch.points[index].t)
    end
    for k = index, #ch.points do
        ch.points[k].t = ch.points[k].t + dt
    end
end

function Ch.setMode(ch, index, mode)
    if ch.points[index] ~= nil then
        ch.points[index].mode = mode
    end
end

-- Zjednoduší seřazené vzorky { t, v } na co nejméně bodů tak, aby se úsečkami mezi nimi průběh odchýlil nejvýš o tol
-- (Ramer-Douglas-Peucker). Krajní vzorky zůstanou.
function Ch.simplify(samples, tol)
    local n = #samples
    if n <= 2 then
        return samples
    end
    local keep = { [1] = true, [n] = true }
    local function recurse(first, last)
        local a, b = samples[first], samples[last]
        local worst, worstIndex = -1, nil
        for i = first + 1, last - 1 do
            local u = (samples[i].t - a.t) / math.max(b.t - a.t, 1e-9)
            local err = math.abs(samples[i].v - (a.v + (b.v - a.v) * u))
            if err > worst then
                worst, worstIndex = err, i
            end
        end
        if worstIndex ~= nil and worst > tol then
            keep[worstIndex] = true
            recurse(first, worstIndex)
            recurse(worstIndex, last)
        end
    end
    recurse(1, n)
    local out = {}
    for i = 1, n do
        if keep[i] then
            out[#out + 1] = samples[i]
        end
    end
    return out
end

-- Kanál z hodnot funkce fn(t) v zadaných časech (výchozí tvar podle dosavadního průběhu).
function Ch.fromFunction(times, fn, mode)
    local ch = Ch.new()
    for _, t in ipairs(times) do
        Ch.addPoint(ch, t, fn(t), mode)
    end
    return ch
end
