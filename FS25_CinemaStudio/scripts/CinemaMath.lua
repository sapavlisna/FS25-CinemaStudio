-- Čistá matematika bez herních API (testovatelná v LuaJIT mimo hru): Hermite pro nerovnoměrné časy, kvaterniony
-- v konvenci YXZ (yaw kolem Y, pitch kolem X, roll kolem Z; pohled podél +Z rigu), ohnisko v mm ↔ vertikální FOV.

CinemaMath = CinemaMath or {}
local M = CinemaMath

function M.clamp(v, lo, hi)
    if v < lo then
        return lo
    end
    if v > hi then
        return hi
    end
    return v
end

-- Index segmentu i takový, že ts[i] <= t < ts[i+1] (ts vzestupně, aspoň 2 prvky).
local function findSegment(ts, t)
    local lo, hi = 1, #ts - 1
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if ts[mid] <= t then
            lo = mid
        else
            hi = mid - 1
        end
    end
    return lo
end
M.findSegment = findSegment

-- Hermite s tangentami z konečných rozdílů (Catmull-Rom pro nerovnoměrné časy). vs[i] = pole n čísel.
-- Na krajích jednostranná tangenta, mimo rozsah drží krajní hodnotu.
function M.hermite(ts, vs, n, t)
    local count = #ts
    local out = {}
    if count == 1 or t <= ts[1] then
        for c = 1, n do out[c] = vs[1][c] end
        return out
    end
    if t >= ts[count] then
        for c = 1, n do out[c] = vs[count][c] end
        return out
    end
    local i = findSegment(ts, t)
    local t1, t2 = ts[i], ts[i + 1]
    local dt = t2 - t1
    local s = (t - t1) / dt
    local s2, s3 = s * s, s * s * s
    local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
    local ia, ib = math.max(i - 1, 1), math.min(i + 2, count)
    for c = 1, n do
        local p1, p2 = vs[i][c], vs[i + 1][c]
        local m1 = i == 1 and (p2 - p1) / dt or (p2 - vs[ia][c]) / (t2 - ts[ia])
        local m2 = i + 1 == count and (p2 - p1) / dt or (vs[ib][c] - p1) / (ts[ib] - t1)
        out[c] = h00 * p1 + h10 * dt * m1 + h01 * p2 + h11 * dt * m2
    end
    return out
end

---------------------------------------------------------------------------------------------------
-- kvaterniony {x, y, z, w}

function M.quatMul(a, b)
    return {
        a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
        a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
        a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
        a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
    }
end

function M.quatNormalize(q)
    local len = math.sqrt(q[1] * q[1] + q[2] * q[2] + q[3] * q[3] + q[4] * q[4])
    if len < 1e-9 then
        return { 0, 0, 0, 1 }
    end
    return { q[1] / len, q[2] / len, q[3] / len, q[4] / len }
end

-- Lineární prolnutí dvou natočení (po zarovnání znaménka); na pár sekund přechodu mezi dvěma cíli stačí.
function M.quatNlerp(a, b, u)
    local sign = M.quatDot(a, b) < 0 and -1 or 1
    return M.quatNormalize({
        a[1] + (b[1] * sign - a[1]) * u, a[2] + (b[2] * sign - a[2]) * u,
        a[3] + (b[3] * sign - a[3]) * u, a[4] + (b[4] * sign - a[4]) * u,
    })
end

-- Úhel (rad) mezi dvěma natočeními, nejkratší cestou.
function M.quatAngle(a, b)
    return 2 * math.acos(math.min(math.abs(M.quatDot(a, b)), 1))
end

function M.quatDot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]
end

function M.quatFromYawPitchRoll(yaw, pitch, roll)
    local qy = { 0, math.sin(yaw * 0.5), 0, math.cos(yaw * 0.5) }
    local qx = { math.sin(pitch * 0.5), 0, 0, math.cos(pitch * 0.5) }
    local qz = { 0, 0, math.sin(roll * 0.5), math.cos(roll * 0.5) }
    return M.quatMul(M.quatMul(qy, qx), qz)
end

-- Rozklad R = Ry(yaw) Rx(pitch) Rz(roll); pitch > 0 = pohled dolů.
function M.quatToYawPitchRoll(q)
    local x, y, z, w = q[1], q[2], q[3], q[4]
    local m02 = 2 * (x * z + w * y)
    local m12 = 2 * (y * z - w * x)
    local m22 = 1 - 2 * (x * x + y * y)
    local m10 = 2 * (x * y + w * z)
    local m11 = 1 - 2 * (x * x + z * z)
    local pitch = math.asin(M.clamp(-m12, -1, 1))
    local yaw = math.atan2(m02, m22)
    local roll = math.atan2(m10, m11)
    return yaw, pitch, roll
end

-- Směr pohledu (+Z rigu) ve světě.
function M.forwardFromYawPitch(yaw, pitch)
    local cp = math.cos(pitch)
    return math.sin(yaw) * cp, -math.sin(pitch), math.cos(yaw) * cp
end

-- Pravá strana pohledu. Svět je pravotočivý s Y nahoru: při pohledu podél +Z je vpravo -X.
function M.rightFromYaw(yaw)
    return -math.cos(yaw), 0, math.sin(yaw)
end

-- Yaw a pitch, které míří ve směru (dx, dy, dz).
function M.yawPitchFromDirection(dx, dy, dz)
    local horizontal = math.sqrt(dx * dx + dz * dz)
    return math.atan2(dx, dz), math.atan2(-dy, horizontal)
end

-- Natočení s pohledem ve směru f a horní stranou co nejblíž u (oba ve světě): yaw a pitch z f, náklon z u.
function M.quatFromForwardUp(fx, fy, fz, ux, uy, uz)
    local yaw, pitch = M.yawPitchFromDirection(fx, fy, fz)
    local sy, cy, sp, cp = math.sin(yaw), math.cos(yaw), math.sin(pitch), math.cos(pitch)
    -- osy x a y kamery bez náklonu; náklon r je pak u = -sin r * x0 + cos r * y0
    local alongX = ux * cy - uz * sy
    local alongY = ux * sy * sp + uy * cp + uz * cy * sp
    return M.quatFromYawPitchRoll(yaw, pitch, math.atan2(-alongX, alongY))
end

-- Horní strana kamery (yaw, pitch) bez náklonu ve světě.
function M.upFromYawPitch(yaw, pitch)
    return math.sin(yaw) * math.sin(pitch), math.cos(pitch), math.cos(yaw) * math.sin(pitch)
end

-- Yaw a pitch kamery, ve které je bod ve směru (dx, dy, dz) na místě (ox, oy) obrazu: 0 = střed, ±1 = kraj
-- (ox > 0 vpravo, oy > 0 nahoře); fovY a aspect jsou objektiv kamery. Bez náklonu.
function M.yawPitchFraming(dx, dy, dz, ox, oy, fovY, aspect)
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 1e-9 then
        return 0, 0
    end
    local tv = math.tan(fovY * 0.5)
    -- směr bodu v kameře (vpravo je -X rigu), po náklonu p: y = ly cos p - sin p
    local lx, ly = -ox * tv * aspect, oy * tv
    local ll = math.sqrt(lx * lx + ly * ly + 1)
    local r, phi = math.sqrt(ly * ly + 1), math.atan2(1, ly)
    local c = math.acos(M.clamp(ll * dy / len / r, -1, 1))
    local _, pitch0 = M.yawPitchFromDirection(dx, dy, dz)
    local pitch = c - phi
    if math.abs(-c - phi - pitch0) < math.abs(pitch - pitch0) then
        pitch = -c - phi
    end
    local zp = ly * math.sin(pitch) + math.cos(pitch)
    return math.atan2(dx, dz) - math.atan2(lx, zp), pitch
end

-- Kvaterniony jedné stopy otočí do stejné polokoule jako předchůdce, aby interpolace šla kratší cestou.
function M.alignQuats(quats)
    local out = {}
    for i, q in ipairs(quats) do
        local c = { q[1], q[2], q[3], q[4] }
        if i > 1 and M.quatDot(out[i - 1], c) < 0 then
            c[1], c[2], c[3], c[4] = -c[1], -c[2], -c[3], -c[4]
        end
        out[i] = c
    end
    return out
end

-- Hermite po složkách nad zarovnanými kvaterniony + normalizace: spojitá úhlová rychlost přes keyframy,
-- žádné přeskoky přes ±π, jaké dělá interpolace Eulerových úhlů.
function M.quatHermite(ts, alignedQuats, t)
    return M.quatNormalize(M.hermite(ts, alignedQuats, 4, t))
end

function M.angleDiff(a, b)
    local d = (b - a) % (2 * math.pi)
    if d > math.pi then
        d = d - 2 * math.pi
    end
    return d
end

---------------------------------------------------------------------------------------------------
-- objektiv: ohnisko v mm (ekvivalent full-frame, výška snímače 24 mm) ↔ vertikální FOV

M.SENSOR_HEIGHT = 24
M.FOCAL_MIN = 10
M.FOCAL_MAX = 600
M.FOCAL_PRESETS = { 14, 24, 35, 50, 85, 135, 200, 400 }

function M.focalToFov(mm)
    return 2 * math.atan(M.SENSOR_HEIGHT / (2 * mm))
end

function M.fovToFocal(fov)
    return M.SENSOR_HEIGHT / (2 * math.tan(fov * 0.5))
end

function M.clampFocal(mm)
    return M.clamp(mm, M.FOCAL_MIN, M.FOCAL_MAX)
end

-- Krok zoomu kolečkem: násobkem, aby byl stejně citelný u 14 i 400 mm.
function M.stepFocal(mm, steps, factor)
    return M.clampFocal(mm * (factor or 1.06) ^ steps)
end

---------------------------------------------------------------------------------------------------
-- easing

function M.smoothstep(u)
    u = M.clamp(u, 0, 1)
    return u * u * (3 - 2 * u)
end

-- Postup úsekem 0..1 jako kubický Hermite s f(0) = 0, f(1) = 1 a sklony m0, m1 na krajích (sklon 1 = rovnoměrně,
-- 0 = zastavení). Pro sklony 0..3 je monotónní, takže kamera nikdy necouvá.
M.EASE_SLOPE_MAX = 3

function M.easeProgress(tau, m0, m1)
    local t2, t3 = tau * tau, tau * tau * tau
    return (t3 - 2 * t2 + tau) * m0 + (-2 * t3 + 3 * t2) + (t3 - t2) * m1
end

function M.easeDerivative(tau, m0, m1)
    local t2 = tau * tau
    return (3 * t2 - 4 * tau + 1) * m0 + (-6 * t2 + 6 * tau) + (3 * t2 - 2 * tau) * m1
end

-- Postup jako kubická Bézierova křivka (0,0) (a, a·m0) (1−b, 1−b·m1) (1,1): sklony m0, m1 na krajích a vliv a, b
-- (jakou část úseku trvá změna rychlosti). Vliv 1/3 je přesně easeProgress. Monotónní pro a·m0 ≤ 1 a b·m1 ≤ 1.
M.INFLUENCE = 1 / 3
M.INFLUENCE_MIN = 0.05
M.INFLUENCE_MAX = 0.95

local function bezier1(s, c1, c2)
    local r = 1 - s
    return 3 * r * r * s * c1 + 3 * r * s * s * c2 + s * s * s
end

local function bezier1d(s, c1, c2)
    local r = 1 - s
    return 3 * r * r * c1 + 6 * r * s * (c2 - c1) + 3 * s * s * (1 - c2)
end

local function solveBezierX(tau, a, b)
    local c1, c2 = a, 1 - b
    if math.abs(a - M.INFLUENCE) < 1e-9 and math.abs(b - M.INFLUENCE) < 1e-9 then
        return tau
    end
    local s = tau
    for _ = 1, 8 do
        local d = bezier1d(s, c1, c2)
        if d < 1e-6 then
            break
        end
        local next = s - (bezier1(s, c1, c2) - tau) / d
        if next < 0 or next > 1 then
            break
        end
        s = next
    end
    if math.abs(bezier1(s, c1, c2) - tau) > 1e-7 then
        local lo, hi = 0, 1
        for _ = 1, 40 do
            s = (lo + hi) * 0.5
            if bezier1(s, c1, c2) < tau then
                lo = s
            else
                hi = s
            end
        end
    end
    return s
end

function M.easeBezier(tau, m0, m1, a, b)
    a, b = a or M.INFLUENCE, b or M.INFLUENCE
    if tau <= 0 then
        return 0
    elseif tau >= 1 then
        return 1
    end
    local s = solveBezierX(tau, a, b)
    return bezier1(s, a * m0, 1 - b * m1)
end

-- Sklon easeBezier (df / dtau).
function M.easeBezierDerivative(tau, m0, m1, a, b)
    a, b = a or M.INFLUENCE, b or M.INFLUENCE
    if tau <= 0 then
        return m0
    elseif tau >= 1 then
        return m1
    end
    local s = solveBezierX(tau, a, b)
    local dx = bezier1d(s, a, 1 - b)
    if dx < 1e-9 then
        return s < 0.5 and m0 or m1
    end
    return bezier1d(s, a * m0, 1 - b * m1) / dx
end

-- Centripetální Catmull-Rom (Barry-Goldman) úseku p1→p2, u v 0..1; p = {x, y, z}. Nedělá smyčky ani hroty
-- u nerovnoměrně rozmístěných bodů, na rozdíl od uniformního.
local function knot(a, b)
    local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    return math.max(math.sqrt(math.sqrt(dx * dx + dy * dy + dz * dz)), 1e-4)
end

local function lerp3(a, b, wa, wb)
    return { a[1] * wa + b[1] * wb, a[2] * wa + b[2] * wb, a[3] * wa + b[3] * wb }
end

function M.catmullRom(p0, p1, p2, p3, u)
    local t1 = knot(p0, p1)
    local t2 = t1 + knot(p1, p2)
    local t3 = t2 + knot(p2, p3)
    local t = t1 + (t2 - t1) * u
    local a1 = lerp3(p0, p1, (t1 - t) / t1, t / t1)
    local a2 = lerp3(p1, p2, (t2 - t) / (t2 - t1), (t - t1) / (t2 - t1))
    local a3 = lerp3(p2, p3, (t3 - t) / (t3 - t2), (t - t2) / (t3 - t2))
    local b1 = lerp3(a1, a2, (t2 - t) / t2, t / t2)
    local b2 = lerp3(a2, a3, (t3 - t) / (t3 - t1), (t - t1) / (t3 - t1))
    return lerp3(b1, b2, (t2 - t) / (t2 - t1), (t - t1) / (t2 - t1))
end

-- Průsečík paprsku s terénem: kroky po paprsku, pak půlení. heightAt(x, z) dodá výšku terénu.
function M.rayTerrain(ox, oy, oz, dx, dy, dz, heightAt, maxDist, step)
    maxDist, step = maxDist or 3000, step or 2
    local prev = 0
    if oy < heightAt(ox, oz) then
        return nil
    end
    local dist = step
    while dist <= maxDist do
        local x, y, z = ox + dx * dist, oy + dy * dist, oz + dz * dist
        if y <= heightAt(x, z) then
            local lo, hi = prev, dist
            for _ = 1, 24 do
                local mid = (lo + hi) * 0.5
                local mx, my, mz = ox + dx * mid, oy + dy * mid, oz + dz * mid
                if my <= heightAt(mx, mz) then
                    hi = mid
                else
                    lo = mid
                end
            end
            return ox + dx * hi, oy + dy * hi, oz + dz * hi
        end
        prev = dist
        dist = dist + step * (1 + dist / 200)
    end
    return nil
end

-- Exponenciální přiblížení k cíli nezávislé na snímkové frekvenci (tau v sekundách).
function M.damp(current, target, tau, dtSec)
    if tau <= 0 then
        return target
    end
    return current + (target - current) * (1 - math.exp(-dtSec / tau))
end
