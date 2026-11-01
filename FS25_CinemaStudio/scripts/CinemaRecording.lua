-- Nahrávání ruční jízdy: vzorky polohy, rychlosti, os a stavů vozidla se zjednoduší na trasu (body s příznakem couvání),
-- křivku rychlosti, křivky os a akce herce, takže jízda jde v editoru dál upravovat. Bez herních API.
-- Čas křivek a akcí je od začátku nahrávky, tedy od startu jízdy herce; křivka rychlosti drží časování, aby osy a akce seděly.

CinemaRecording = CinemaRecording or {}
local Rc = CinemaRecording
local Ch = CinemaChannels
local A = CinemaActions

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
