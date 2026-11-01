-- Krabice: skutečné věci ve světě (soupravy, palety, balíky), které se přenesou jinam jako celek. Vzájemné rozestavení
-- zůstane, celek se natočí kolem svého středu a každá věc se usadí na terén ve stejné výšce nad ním jako předtím.
-- Patří editoru, ne záběru: přežije přepnutí záběru (ne restart hry). Položka { kind = "vehicle" | "bale", uid }.
-- Souprava jde celá (i zapřažené nářadí) a s ní náklad, který leží na korbě (balíky, palety). Ve hře mění svět jen server.

CinemaBox = CinemaBox or { items = {} }
local B = CinemaBox
local W = CinemaWorld
local Pr = CinemaProps

B.LIFT = 0.3          -- m; o tolik výš se věc postaví a dopadne (nezapadne do terénu, který je jinde výš)
B.CARGO_HEIGHT = 4    -- m nad podlahou vozidla, kam ještě sahá náklad
B.BALE_SIZE = 1.2     -- m; půlka strany čtverce, kterým se balík ukazuje při pokládání

function B.count()
    return #B.items
end

function B.has(kind, uid)
    for _, item in ipairs(B.items) do
        if item.kind == kind and item.uid == uid then
            return true
        end
    end
    return false
end

-- Přidá věc do krabice, nebo ji vyndá, když už v ní je. Vrací true, když v ní teď je.
function B.toggle(kind, uid)
    for i, item in ipairs(B.items) do
        if item.kind == kind and item.uid == uid then
            table.remove(B.items, i)
            return false
        end
    end
    B.items[#B.items + 1] = { kind = kind, uid = uid }
    return true
end

function B.toggleVehicle(v)
    return B.toggle("vehicle", W.uid(W.rootOf(v)))
end

function B.hasVehicle(v)
    return B.has("vehicle", W.uid(W.rootOf(v)))
end

function B.toggleBale(bale)
    return B.toggle("bale", Pr.baleUid(bale))
end

function B.clear()
    B.items = {}
end

-- Leží bod (x, y, z) na vozidle v (v jeho obrysu, nad podlahou)?
local function onVehicle(v, x, y, z)
    local size = v.size or {}
    local lx, ly, lz = worldToLocal(v.rootNode, x, y, z)
    return math.abs(lx - (size.widthOffset or 0)) <= (size.width or 3) * 0.5
        and math.abs(lz - (size.lengthOffset or 0)) <= (size.length or 5) * 0.5
        and ly > -0.5 and ly < (size.height or 3) + B.CARGO_HEIGHT
end

-- Co se přenese: { starts = { start soupravy… }, bales = { { bale, p } } }. Bez roots a bales obsah krabice.
function B.collect(roots, bales)
    if roots == nil then
        roots, bales = {}, {}
        for _, item in ipairs(B.items) do
            if item.kind == "vehicle" then
                roots[#roots + 1] = W.find(item.uid)
            else
                bales[#bales + 1] = Pr.findBale(item.uid)
            end
        end
    end
    local set = { starts = {}, bales = {} }
    local members, carriers, baleSet = {}, {}, {}
    local function addRoot(root)
        if members[W.uid(root)] then
            return
        end
        local start = W.captureStart(root)
        set.starts[#set.starts + 1] = start
        for _, e in ipairs(start.entries) do
            members[e.uid] = true
            carriers[#carriers + 1] = W.find(e.uid)
        end
    end
    local function addBale(bale)
        if not baleSet[bale] then
            baleSet[bale] = true
            set.bales[#set.bales + 1] = { bale = bale, p = Pr.readBale(bale) }
        end
    end
    for _, root in ipairs(roots) do
        addRoot(W.rootOf(root))
    end
    for _, bale in ipairs(bales or {}) do
        addBale(bale)
    end
    -- náklad: volně ležící palety a balíky na korbě vozidel z krabice (i náklad nákladu)
    local index = 1
    while index <= #carriers do
        local carrier = carriers[index]
        for _, v in ipairs(carrier ~= nil and W.vehicles() or {}) do
            if W.rootOf(v) == v and not members[W.uid(v)] and v.rootNode ~= nil and entityExists(v.rootNode)
                and onVehicle(carrier, getWorldTranslation(v.rootNode)) then
                addRoot(v)
            end
        end
        for _, bale in ipairs(carrier ~= nil and Pr.bales() or {}) do
            if onVehicle(carrier, getWorldTranslation(bale.nodeId)) then
                addBale(bale)
            end
        end
        index = index + 1
    end
    return set
end

function B.isEmpty(set)
    return #set.starts == 0 and #set.bales == 0
end

-- Střed rozestavení (x, z): průměr poloh souprav a balíků.
function B.center(set)
    local sx, sz, n = 0, 0, 0
    for _, start in ipairs(set.starts) do
        for _, e in ipairs(start.entries) do
            sx, sz, n = sx + e.x, sz + e.z, n + 1
        end
    end
    for _, b in ipairs(set.bales) do
        sx, sz, n = sx + b.p.x, sz + b.p.z, n + 1
    end
    if n == 0 then
        return 0, 0
    end
    return sx / n, sz / n
end

-- Kam padne bod (x, y, z), když se střed (cx, cz) přenese na (tx, tz) a celek otočí o rot (jako přírůstek ry).
function B.pose(cx, cz, tx, tz, rot, x, y, z)
    local dx, dz = x - cx, z - cz
    local c, s = math.cos(rot), math.sin(rot)
    local nx, nz = tx + dx * c + dz * s, tz - dx * s + dz * c
    return nx, W.terrainY(nx, nz) + (y - W.terrainY(x, z)) + B.LIFT, nz
end

-- Obrysy věcí na zemi pro náhled pokládání: { { {x, z} × 4 } }, ve světě, kde věci stojí teď.
function B.outlines(set)
    local list = {}
    for _, start in ipairs(set.starts) do
        for _, e in ipairs(start.entries) do
            local v = W.find(e.uid)
            if v ~= nil then
                local size = v.size or {}
                local w, l = (size.width or 3) * 0.5, (size.length or 5) * 0.5
                local wo, lo = size.widthOffset or 0, size.lengthOffset or 0
                local quad = {}
                for _, corner in ipairs({ { -w, -l }, { w, -l }, { w, l }, { -w, l } }) do
                    local x, _, z = localToWorld(v.rootNode, corner[1] + wo, 0, corner[2] + lo)
                    quad[#quad + 1] = { x, z }
                end
                list[#list + 1] = quad
            end
        end
    end
    for _, b in ipairs(set.bales) do
        local r = B.BALE_SIZE
        list[#list + 1] = { { b.p.x - r, b.p.z - r }, { b.p.x + r, b.p.z - r }, { b.p.x + r, b.p.z + r }, { b.p.x - r, b.p.z + r } }
    end
    return list
end

-- Přenese věci: střed rozestavení na (tx, tz), natočené o rot. Vrací počet přenesených věcí, nebo nil a důvod.
function B.place(set, tx, tz, rot)
    if g_currentMission ~= nil and not g_currentMission:getIsServer() then
        return nil, "notServer"
    end
    local cx, cz = B.center(set)
    local moved = 0
    for _, start in ipairs(set.starts) do
        local ok = W.resetStart(start, function(e)
            local x, y, z = B.pose(cx, cz, tx, tz, rot, e.x, e.y, e.z)
            return x, y, z, e.rx, e.ry + rot, e.rz
        end)
        if ok then
            moved = moved + #start.entries
        end
    end
    for _, b in ipairs(set.bales) do
        if not b.bale.isDeleted then
            local p = {}
            for k, v in pairs(b.p) do
                p[k] = v
            end
            p.x, p.y, p.z = B.pose(cx, cz, tx, tz, rot, b.p.x, b.p.y, b.p.z)
            p.ry = b.p.ry + rot
            Pr.placeBale(b.bale, p)
            moved = moved + 1
        end
    end
    return moved
end
