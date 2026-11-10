-- Prostorová dráha přes body s tabulkou délky oblouku: poloha podle ujeté vzdálenosti. Úseky jsou kubické Bézierovy
-- křivky; táhla bodu jsou automatická (přesně centripetální Catmull-Rom), nebo zadaná (vlastní tvar, {0, 0, 0} = roh).
-- Dráha nezná čas; kdy kamera kde je, určuje časování v CinemaShot. Bez herních API.

CinemaPath = CinemaPath or {}
local P = CinemaPath
local M = CinemaMath

P.SAMPLES = 24

local function dist3(a, b)
    local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function knot(a, b)
    return math.max(math.sqrt(dist3(a, b)), 1e-4)
end

-- Automatická táhla bodu i (vstup a výstup, relativně k bodu): tečna centripetálního Catmull-Romu (Barry-Goldman)
-- převedená na Bézier. Krajní body mají za sebou zrcadlený pomyslný bod, stejně jako dřív.
function P.autoHandles(pts, i)
    local n = #pts
    local p = pts[i]
    if n < 2 then
        return { 0, 0, 0 }, { 0, 0, 0 }
    end
    local prev = pts[i - 1] or { 2 * p[1] - pts[i + 1][1], 2 * p[2] - pts[i + 1][2], 2 * p[3] - pts[i + 1][3] }
    local next = pts[i + 1] or { 2 * p[1] - prev[1], 2 * p[2] - prev[2], 2 * p[3] - prev[3] }
    local d0, d1 = knot(prev, p), knot(p, next)
    local m = {}
    for c = 1, 3 do
        m[c] = (p[c] - prev[c]) / d0 - (next[c] - prev[c]) / (d0 + d1) + (next[c] - p[c]) / d1
    end
    -- výška se nesmí podstřelit: rovný úsek před stoupáním by jinak nejdřív klesl (tečka Catmull-Romu míří nahoru už před
    -- bodem). Sklon výšky se v bodě vynuluje, když se směr mění nebo na jedné straně není, a jinak omezí (Fritsch-Carlson).
    local sa, sb = (p[2] - prev[2]) / d0, (next[2] - p[2]) / d1
    if sa * sb <= 0 then
        m[2] = 0
    else
        local limit = 3 * math.min(math.abs(sa), math.abs(sb))
        m[2] = math.max(math.min(m[2], limit), -limit)
    end
    local hin, hout = {}, {}
    for c = 1, 3 do
        hin[c] = -m[c] * d0 / 3
        hout[c] = m[c] * d1 / 3
    end
    return hin, hout
end

-- Skutečná táhla bodu i: zadaná, jinak automatická.
function P.handles(pts, handles, i)
    local h = handles ~= nil and handles[i] or nil
    local hin, hout
    if h == nil or h.hin == nil or h.hout == nil then
        hin, hout = P.autoHandles(pts, i)
    end
    if h ~= nil then
        hin, hout = h.hin or hin, h.hout or hout
    end
    return hin, hout
end

local function pointOnSegment(path, i, u)
    local pts = path.pts
    local a = pts[i]
    if path.zero[i] then
        return { a[1], a[2], a[3] }
    end
    local b, c1, c2 = pts[i + 1], path.c1[i], path.c2[i]
    local r = 1 - u
    local w0, w1, w2, w3 = r * r * r, 3 * r * r * u, 3 * r * u * u, u * u * u
    return {
        w0 * a[1] + w1 * c1[1] + w2 * c2[1] + w3 * b[1],
        w0 * a[2] + w1 * c1[2] + w2 * c2[2] + w3 * b[2],
        w0 * a[3] + w1 * c1[3] + w2 * c2[3] + w3 * b[3],
    }
end

-- pts = { {x, y, z}, ... }, aspoň jeden bod; handles[i] = { hin, hout } (nil = automaticky).
function P.build(pts, handles, samples)
    samples = samples or P.SAMPLES
    local path = { pts = pts, zero = {}, seg = {}, cum = { 0 }, c1 = {}, c2 = {}, hin = {}, hout = {} }
    for i = 1, #pts do
        path.hin[i], path.hout[i] = P.handles(pts, handles, i)
    end
    for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        path.c1[i] = { a[1] + path.hout[i][1], a[2] + path.hout[i][2], a[3] + path.hout[i][3] }
        path.c2[i] = { b[1] + path.hin[i + 1][1], b[2] + path.hin[i + 1][2], b[3] + path.hin[i + 1][3] }
        path.zero[i] = dist3(pts[i], pts[i + 1]) < 1e-4
        local us, ss = { 0 }, { 0 }
        local prev = pts[i]
        local length = 0
        if not path.zero[i] then
            for k = 1, samples do
                local u = k / samples
                local p = pointOnSegment(path, i, u)
                length = length + dist3(prev, p)
                us[#us + 1], ss[#ss + 1] = u, length
                prev = p
            end
        end
        path.seg[i] = { us = us, ss = ss, length = length }
        path.cum[i + 1] = path.cum[i] + length
    end
    path.length = path.cum[#path.cum]
    return path
end

-- Délka od začátku dráhy k bodu i.
function P.lengthAt(path, i)
    return path.cum[i] or path.length
end

function P.segmentLength(path, i)
    return path.seg[i] ~= nil and path.seg[i].length or 0
end

-- Bod v úseku i ve vzdálenosti d od jeho začátku.
function P.pointInSegment(path, i, d)
    local seg = path.seg[i]
    if seg == nil then
        local p = path.pts[#path.pts]
        return p[1], p[2], p[3]
    end
    if seg.length <= 0 or d <= 0 then
        local p = path.pts[i]
        return p[1], p[2], p[3]
    end
    if d >= seg.length then
        local p = path.pts[i + 1]
        return p[1], p[2], p[3]
    end
    local k = M.findSegment(seg.ss, d)
    local s0, s1 = seg.ss[k], seg.ss[k + 1]
    local u = seg.us[k] + (seg.us[k + 1] - seg.us[k]) * (d - s0) / (s1 - s0)
    local p = pointOnSegment(path, i, u)
    return p[1], p[2], p[3]
end

-- Bod ve vzdálenosti s od začátku celé dráhy.
function P.pointAt(path, s)
    local n = #path.pts
    if n == 1 or s <= 0 then
        local p = path.pts[1]
        return p[1], p[2], p[3]
    end
    if s >= path.length then
        local p = path.pts[n]
        return p[1], p[2], p[3]
    end
    local i = M.findSegment(path.cum, s)
    return P.pointInSegment(path, i, s - path.cum[i])
end
