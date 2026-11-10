-- Zóny na poli: kus pole, který se po nastavení celého pole přepíše na „sklizeno“ nebo „nesklizeno“. Zóna je seznam
-- rovnoběžníků (kvádrů shora) { sx, sz, wx, wz, hx, hz }: start, roh na straně šířky a roh na straně výšky, jako
-- DensityMapParallelogram ve hře. Zóna podle kurzu Courseplay drží i osy projetých řádků (pro řádky slámy).
-- Čistá geometrie a zápis, bez herních API.

CinemaZones = CinemaZones or {}
local Z = CinemaZones

Z.MIN_SIDE = 0.5 -- m; kratší strana zóny nebo úsek kurzu se zahodí
Z.CLIP_STEP = 2 -- m; šířka pruhů, na které se rozdělí kvádr přesahující pole
Z.CLIP_MAX = 60 -- nejvíc pruhů z jednoho kvádru (větší kvádr má pruhy širší)
Z.MAX_QUADS = 1500 -- kvádrů ve všech zónách pole (každý je jedna úloha hry)
Z.MERGE_ANGLE = math.rad(3) -- úseky kurzu, které se odchylují méně, se slijí do jednoho
Z.DEFAULT_WIDTH = 12 -- m; pracovní šířka kurzu, když ji kurz neřekne

local function hypot(x, z)
    return math.sqrt(x * x + z * z)
end

local function split(text, sep)
    local out, from = {}, 1
    while true do
        local i = text:find(sep, from, true)
        if i == nil then
            out[#out + 1] = text:sub(from)
            return out
        end
        out[#out + 1] = text:sub(from, i - 1)
        from = i + 1
    end
end

local function numbers(part)
    local list = {}
    for n in part:gmatch("%S+") do
        list[#list + 1] = tonumber(n)
    end
    return list
end

---------------------------------------------------------------------------------------------------
-- zápis: zóny odděleny "|", v zóně "režim/původ/kvádry/čáry" (kvádry a čáry odděleny ";", čísla mezerou)

function Z.encode(zones)
    if #zones == 0 then
        return nil
    end
    local parts = {}
    for _, zone in ipairs(zones) do
        local qs, ls = {}, {}
        for _, q in ipairs(zone.quads) do
            qs[#qs + 1] = string.format("%.2f %.2f %.2f %.2f %.2f %.2f", q[1], q[2], q[3], q[4], q[5], q[6])
        end
        for _, l in ipairs(zone.lines or {}) do
            ls[#ls + 1] = string.format("%.1f %.1f %.1f %.1f", l[1], l[2], l[3], l[4])
        end
        parts[#parts + 1] = table.concat({ zone.mode, zone.src or "rect", table.concat(qs, ";"), table.concat(ls, ";") }, "/")
    end
    return table.concat(parts, "|")
end

function Z.decode(text)
    local zones = {}
    if text == nil or text == "" then
        return zones
    end
    for _, part in ipairs(split(text, "|")) do
        local f = split(part, "/")
        local zone = { mode = f[1] == "standing" and "standing" or "cut", src = f[2] or "rect", quads = {}, lines = {} }
        for _, q in ipairs(split(f[3] or "", ";")) do
            local n = numbers(q)
            if #n == 6 then
                zone.quads[#zone.quads + 1] = n
            end
        end
        for _, l in ipairs(split(f[4] or "", ";")) do
            local n = numbers(l)
            if #n == 4 then
                zone.lines[#zone.lines + 1] = n
            end
        end
        if #zone.quads > 0 then
            zones[#zones + 1] = zone
        end
    end
    return zones
end

-- Počty zón: sklizeno, nesklizeno, kvádrů celkem.
function Z.summary(zones)
    local cut, standing, quads = 0, 0, 0
    for _, zone in ipairs(zones) do
        if zone.mode == "cut" then
            cut = cut + 1
        else
            standing = standing + 1
        end
        quads = quads + #zone.quads
    end
    return cut, standing, quads
end

-- Osy projetých řádků ve sklizených zónách (jen ty, které je mají).
function Z.cutLines(zones)
    local lines = {}
    for _, zone in ipairs(zones) do
        if zone.mode == "cut" then
            for _, l in ipairs(zone.lines) do
                lines[#lines + 1] = l
            end
        end
    end
    return lines
end

---------------------------------------------------------------------------------------------------
-- tvary

-- Obdélník ze tří kliknutí: strana A–B a bod C, který říká, na kterou stranu a jak daleko od ní se obdélník rozšíří.
function Z.rectQuad(ax, az, bx, bz, cx, cz)
    local dx, dz = bx - ax, bz - az
    local len = hypot(dx, dz)
    if len < Z.MIN_SIDE then
        return nil
    end
    local nx, nz = -dz / len, dx / len
    local d = (cx - ax) * nx + (cz - az) * nz
    if math.abs(d) < Z.MIN_SIDE then
        return nil
    end
    return { ax, az, bx, bz, ax + nx * d, az + nz * d }
end

-- Pruh široký width kolem úsečky (x1, z1)–(x2, z2); nil u příliš krátké.
function Z.stripQuad(x1, z1, x2, z2, width)
    local dx, dz = x2 - x1, z2 - z1
    local len = hypot(dx, dz)
    if len < Z.MIN_SIDE then
        return nil
    end
    local h = width * 0.5
    local nx, nz = -dz / len * h, dx / len * h
    return { x1 - nx, z1 - nz, x2 - nx, z2 - nz, x1 + nx, z1 + nz }
end

-- Čtyři rohy kvádru v pořadí kolem dokola.
function Z.corners(q)
    return { { q[1], q[2] }, { q[3], q[4] }, { q[3] + q[5] - q[1], q[4] + q[6] - q[2] }, { q[5], q[6] } }
end

local function allInside(q, inside)
    for _, c in ipairs(Z.corners(q)) do
        if not inside(c[1], c[2]) then
            return false
        end
    end
    return true
end

-- Kvádr jen v poli: celý, když všechny rohy leží v poli (inside(x, z)), jinak pruhy po CLIP_STEP, které v poli leží celé.
-- Zóna nesmí zasáhnout půdu mimo pole (úloha hry přepíše plodinu v celé ploše).
function Z.clip(q, inside)
    if allInside(q, inside) then
        return { q }
    end
    local vx, vz = q[5] - q[1], q[6] - q[2]
    local n = math.max(1, math.ceil(hypot(vx, vz) / math.max(Z.CLIP_STEP, hypot(vx, vz) / Z.CLIP_MAX)))
    local out = {}
    for k = 0, n - 1 do
        local f0, f1 = k / n, (k + 1) / n
        local s = { q[1] + vx * f0, q[2] + vz * f0, q[3] + vx * f0, q[4] + vz * f0, q[1] + vx * f1, q[2] + vz * f1 }
        if allInside(s, inside) then
            out[#out + 1] = s
        end
    end
    return out
end

-- Rovnoběžné čáry po spacing metrech uvnitř kvádru, ve směru strany start–šířka.
function Z.quadLines(q, spacing)
    local vx, vz = q[5] - q[1], q[6] - q[2]
    local n = math.max(1, math.floor(hypot(vx, vz) / math.max(spacing, 1) + 0.5))
    local out = {}
    for k = 0, n - 1 do
        local f = (k + 0.5) / n
        out[#out + 1] = { q[1] + vx * f, q[2] + vz * f, q[3] + vx * f, q[4] + vz * f }
    end
    return out
end

---------------------------------------------------------------------------------------------------
-- kurz: úseky { x1, z1, x2, z2 } v pořadí, v jakém je stroj jede

-- Souvislé úseky téměř jedním směrem se slijí do jednoho: kurz Courseplay má bod co pár metrů, ale kvádr stačí na celý řádek.
function Z.merge(lines)
    local out, cur = {}, nil
    for _, l in ipairs(lines) do
        local dx, dz = l[3] - l[1], l[4] - l[2]
        if hypot(dx, dz) > 1e-6 then
            local joined = false
            if cur ~= nil and hypot(l[1] - cur[3], l[2] - cur[4]) < Z.MIN_SIDE then
                local ax, az = cur[3] - cur[1], cur[4] - cur[2]
                local angle = math.abs(math.atan2(ax * dz - az * dx, ax * dx + az * dz))
                if hypot(ax, az) < 1 or angle <= Z.MERGE_ANGLE then
                    cur[3], cur[4] = l[3], l[4]
                    joined = true
                end
            end
            if not joined then
                cur = { l[1], l[2], l[3], l[4] }
                out[#out + 1] = cur
            end
        end
    end
    return out
end

-- Nejbližší bod kurzu k (x, z): { i = úsek, t = 0..1 v úseku, d = vzdálenost, x, z }; nil bez úseků.
function Z.project(lines, x, z)
    local best = nil
    for i, l in ipairs(lines) do
        local dx, dz = l[3] - l[1], l[4] - l[2]
        local len2 = dx * dx + dz * dz
        local t = len2 > 1e-9 and ((x - l[1]) * dx + (z - l[2]) * dz) / len2 or 0
        t = math.max(0, math.min(1, t))
        local px, pz = l[1] + dx * t, l[2] + dz * t
        local d = hypot(x - px, z - pz)
        if best == nil or d < best.d then
            best = { i = i, t = t, d = d, x = px, z = pz }
        end
    end
    return best
end

-- Část kurzu od začátku po bod hit (výsledek project): úseky před ním celé a z úseku s ním jen kus. lead (m) je
-- předsazení: kurz se protáhne dál za bod po jízdě kurzem (kombajn sklízí žacím stolem před sebou, ne středem); na konci
-- řádku končí, přes obrat se nejede.
function Z.upTo(lines, hit, lead)
    local out = {}
    for i = 1, hit.i - 1 do
        out[#out + 1] = lines[i]
    end
    local l = lines[hit.i]
    if l == nil then
        return out
    end
    if hypot(hit.x - l[1], hit.z - l[2]) >= Z.MIN_SIDE then
        out[#out + 1] = { l[1], l[2], hit.x, hit.z }
    end
    local ex, ez, remaining, i = hit.x, hit.z, lead or 0, hit.i
    while remaining > 1e-6 do
        local seg = lines[i]
        local left = hypot(seg[3] - ex, seg[4] - ez)
        if left >= remaining then
            local f = remaining / left
            out[#out + 1] = { ex, ez, ex + (seg[3] - ex) * f, ez + (seg[4] - ez) * f }
            break
        end
        out[#out + 1] = { ex, ez, seg[3], seg[4] }
        remaining = remaining - left
        local nxt = lines[i + 1]
        if nxt == nil or hypot(nxt[1] - seg[3], nxt[2] - seg[4]) >= Z.MIN_SIDE then
            break
        end
        i, ex, ez = i + 1, nxt[1], nxt[2]
    end
    return out
end

function Z.length(lines)
    local sum = 0
    for _, l in ipairs(lines) do
        sum = sum + hypot(l[3] - l[1], l[4] - l[2])
    end
    return sum
end

-- Pruhy pracovní šířky podél úseků kurzu.
function Z.corridor(lines, width)
    local quads = {}
    for _, l in ipairs(lines) do
        local q = Z.stripQuad(l[1], l[2], l[3], l[4], width)
        if q ~= nil then
            quads[#quads + 1] = q
        end
    end
    return quads
end

-- Zóna podle kurzu až do bodu hit (a lead metrů za něj): sklizené pruhy oříznuté na pole (noClip = neřezat, pole hlídá hra);
-- nil, když z nich nic nezbude.
function Z.courseZone(lines, hit, width, inside, lead, noClip)
    local done = Z.merge(Z.upTo(lines, hit, lead))
    local quads = {}
    for _, q in ipairs(Z.corridor(done, width)) do
        for _, part in ipairs(noClip and { q } or Z.clip(q, inside)) do
            quads[#quads + 1] = part
        end
    end
    if #quads == 0 then
        return nil
    end
    return { mode = "cut", src = "course", quads = quads, lines = done }
end

-- Zóna z kvádru oříznutého na pole, s čarami řádků po spacing (pro slámu); nil, když nic nezbude.
function Z.rectZone(mode, q, inside, spacing, noClip)
    local quads = noClip and { q } or Z.clip(q, inside)
    if #quads == 0 then
        return nil
    end
    local lines = {}
    if mode == "cut" then
        for _, l in ipairs(Z.quadLines(q, spacing)) do
            if inside(l[1], l[2]) and inside(l[3], l[4]) then
                lines[#lines + 1] = l
            end
        end
    end
    return { mode = mode, src = "rect", quads = quads, lines = lines }
end
