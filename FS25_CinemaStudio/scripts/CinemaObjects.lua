-- Objekty ve světě s akcemi na ose: brány, vrata a dveře (AnimatedObject, na mapě i v budovách), světla a výroba budov
-- a stroje (vozidla, která nejezdí). obj = { id, type = "anim" | "placeable" | "vehicle", name, actions }:
--   anim: saveId, x, z (saveId se v různých budovách opakuje, objekt se hledá i podle polohy);
--   placeable, vehicle: uid.
-- Akce mají tvar jako u herců (CinemaActions), t je od začátku záběru. Provádí je CinemaActions: objekt mu dává cíl
-- (O.actor) — vozidlo, nebo obal { uniqueId, world = true, anim | placeable }. Ve hře mění svět server (v MP host).

CinemaObjects = CinemaObjects or {}
local O = CinemaObjects
local W = CinemaWorld

O.PICK_PX = 30
O.FIND_RADIUS = 3 -- m; jak daleko od zapamatované polohy se brána ještě najde
O.TYPES = { "anim", "placeable", "vehicle" }

---------------------------------------------------------------------------------------------------
-- co ve světě je

-- Animované objekty se nikde nevypisují: zapisují se při načtení (mapa se načítá až po módech).
O.animated = setmetatable({}, { __mode = "k" })
-- Utils.appendedFunction zahodí návratovou hodnotu a hra pak každý objekt bere jako nenačtený (brány nejdou otevřít).
if AnimatedObject ~= nil and AnimatedObject.load ~= nil and not AnimatedObject.cinemaStudioHooked then
    AnimatedObject.cinemaStudioHooked = true
    local load = AnimatedObject.load
    AnimatedObject.load = function(self, ...)
        local ok = load(self, ...)
        if ok then
            O.animated[self] = true
        end
        return ok
    end
end

local function usableAnim(a)
    return a ~= nil and not a.isDeleted and a.animation ~= nil and a.nodeId ~= nil and a.nodeId ~= 0 and entityExists(a.nodeId)
end

function O.animatedObjects()
    local list = {}
    for a in pairs(O.animated) do
        if usableAnim(a) then
            list[#list + 1] = a
        end
    end
    return list
end

function O.placeables()
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    return system ~= nil and system.placeables or {}
end

local function placeableUid(p)
    if p.getUniqueId ~= nil then
        return p:getUniqueId()
    end
    return p.uniqueId
end

function O.findPlaceable(uid)
    for _, p in ipairs(O.placeables()) do
        if uid ~= nil and placeableUid(p) == uid then
            return p
        end
    end
    return nil
end

function O.lightGroups(p)
    local spec = p.spec_lights
    if spec ~= nil and spec.groups ~= nil and #spec.groups > 0 and p.setGroupIsActive ~= nil then
        return spec.groups
    end
    return nil
end

function O.productionPoint(p)
    local spec = p.spec_productionPoint
    local pp = spec ~= nil and spec.productionPoint or nil
    if pp ~= nil and pp.productions ~= nil and #pp.productions > 0 and pp.setProductionState ~= nil then
        return pp
    end
    return nil
end

function O.productionEnabled(pp, id)
    if pp.getIsProductionEnabled ~= nil then
        return pp:getIsProductionEnabled(id) == true
    end
    for _, production in ipairs(pp.activeProductions or {}) do
        if production.id == id then
            return true
        end
    end
    return false
end

-- Budova, které brána patří (nil u brány z mapy).
local function ownerOf(a)
    for _, p in ipairs(O.placeables()) do
        for _, spec in ipairs({ p.spec_animatedObjects or false, p.spec_fence or false }) do
            for _, other in ipairs(spec and spec.animatedObjects or {}) do
                if other == a then
                    return p
                end
            end
        end
    end
    return nil
end

local function placeableName(p)
    if p.getName ~= nil then
        local ok, name = pcall(p.getName, p)
        if ok and name ~= nil then
            return name
        end
    end
    return "?"
end

-- Kde brána je: střed jejích pohyblivých dílů (u dvoukřídlé mezi panty). nodeId je u brány v budově kořen celé budovy,
-- takže všechny brány budovy (vjezd farmy z mapy) by byly v jejím počátku, mimo bránu.
function O.animPos(a)
    local n, sx, sy, sz = 0, 0, 0, 0
    for _, part in ipairs(a.animation ~= nil and a.animation.parts or {}) do
        if part.node ~= nil and entityExists(part.node) then
            local x, y, z = getWorldTranslation(part.node)
            n, sx, sy, sz = n + 1, sx + x, sy + y, sz + z
        end
    end
    if n > 0 then
        return sx / n, sy / n, sz / n
    end
    return getWorldTranslation(a.nodeId)
end

function O.animName(a)
    local owner = ownerOf(a)
    -- brány budovy mají společný uzel, liší se jen saveId
    return owner ~= nil and string.format("%s – %s", placeableName(owner), tostring(a.saveId)) or getName(a.nodeId)
end

-- Brána podle saveId a polohy; poloha se porovná s O.animPos i s nodeId (dřív uložené objekty mají polohu uzlu).
function O.findAnim(saveId, x, z)
    local best, bestD = nil, O.FIND_RADIUS
    for _, a in ipairs(O.animatedObjects()) do
        if saveId == nil or a.saveId == saveId then
            local ax, _, az = O.animPos(a)
            local nx, _, nz = getWorldTranslation(a.nodeId)
            local d = math.min(math.sqrt((ax - x) ^ 2 + (az - z) ^ 2), math.sqrt((nx - x) ^ 2 + (nz - z) ^ 2))
            if d <= bestD then
                best, bestD = a, d
            end
        end
    end
    return best
end

-- Brána do koncové polohy: s instant hned (reset, náhled), jinak se otevírá a zavírá jako po klávese hráče.
function O.setAnimTime(a, t)
    a.animation.direction = 0
    a:setAnimTime(t, true)
    if a.raiseActive ~= nil then
        a:raiseActive()
    end
end

function O.setAnimOpen(a, open, instant)
    if instant then
        O.setAnimTime(a, open and 1 or 0)
    elseif a.setDirection ~= nil then
        a:setDirection(open and 1 or -1)
    else
        a.animation.direction = open and 1 or -1
        a:raiseActive()
    end
end

---------------------------------------------------------------------------------------------------
-- vodní hadice SprayDrone (vlek Max / Middle, pumpa): zapojení se zapamatuje a zopakuje veřejnými příkazy hadice
-- (vzít, připojit, odložit — jdou i přes síť); link = { source = uid zdroje | pond = true, port, target, x, y, z, dx, dz, valve }

local function hoseEnv()
    local env = _G["FS25_SprayDroneTrailer"]
    return env ~= nil and env.SprayDroneWaterHose or nil
end

function O.hoseSpec(v)
    local H = hoseEnv()
    local spec = H ~= nil and v[H.SPEC_NAME] or nil
    if spec ~= nil and spec.hoses ~= nil and #spec.hoses > 0 and v.sprayDroneWaterHoseCommand ~= nil then
        return spec
    end
    return nil
end

-- Současné zapojení hadice sub (u zdroje polohu v jeho souřadnicích, u rybníka ve světových); nil, když hadice není zapojená.
function O.readHose(v, sub)
    local spec = O.hoseSpec(v)
    local h = spec ~= nil and spec.hoses[sub] or nil
    if h == nil or not h.out or h.held then
        return nil
    end
    local link = { port = h.port, target = h.targetPort, x = h.srcX, y = h.srcY, z = h.srcZ, dx = h.srcDX, dz = h.srcDZ,
        valve = h.valveOpen or nil }
    if h.pond then
        link.pond = true
    elseif h.source ~= nil and not h.source.isDeleted then
        link.source = W.uid(h.source)
    else
        return nil
    end
    return link
end

local function sameLink(a, b)
    return a ~= nil and b ~= nil and a.source == b.source and a.pond == b.pond and a.port == b.port and a.target == b.target
end

-- Hadici sub zapojí podle link (stejně jako hráč: vezme ze spojky a připojí), bez link ji odpojí.
function O.applyHose(v, sub, link)
    local H = hoseEnv()
    local spec = O.hoseSpec(v)
    local h = spec ~= nil and spec.hoses[sub] or nil
    if h == nil then
        return
    end
    local function command(cmd, target, arg, x, y, z, dx, dz)
        v:sprayDroneWaterHoseCommand(cmd, target, arg, nil, x, y, z, dx or 0, 0, dz or 1, sub)
    end
    if link == nil then
        if h.out then
            command(H.CMD_DROP)
        end
        return
    end
    if sameLink(O.readHose(v, sub), link) then
        return
    end
    local target, x, y, z, dx, dz = nil, link.x, link.y, link.z, link.dx, link.dz
    if not link.pond then
        target = W.find(link.source)
        if target == nil then
            return
        end
        x, y, z = localToWorld(target.rootNode, link.x, link.y, link.z)
        dx, _, dz = localDirectionToWorld(target.rootNode, link.dx or 0, 0, link.dz or 1)
    end
    if h.out then
        command(H.CMD_DROP)
    end
    command(H.CMD_TAKE, nil, link.port, x, y, z, dx, dz)
    command(H.CMD_CONNECT, target, link.pond and H.POND_ARG or (link.target or 0), x, y, z, dx, dz)
    if link.valve and not h.valveOpen and H.CMD_VALVE ~= nil then
        command(H.CMD_VALVE)
    end
end

-- Název hadice podle první spojky (pumpa má vstup a výstup).
local function hoseLabel(h, i)
    local kind = h.ports ~= nil and h.ports[1] ~= nil and h.ports[1].kind or nil
    if kind == "sink" then
        return g_i18n:getText("cine_hose_out")
    elseif kind == "inlet" or kind == "pond" then
        return g_i18n:getText("cine_hose_in")
    end
    return string.format(g_i18n:getText("cine_hose_n"), i)
end

---------------------------------------------------------------------------------------------------
-- objekt na ose

function O.fromAnim(a)
    local x, _, z = O.animPos(a)
    return { type = "anim", saveId = a.saveId, x = x, z = z, name = O.animName(a), actions = {} }
end

function O.fromPlaceable(p)
    return { type = "placeable", uid = placeableUid(p), name = placeableName(p), actions = {} }
end

function O.fromVehicle(v)
    local root = W.rootOf(v)
    return { type = "vehicle", uid = W.uid(root), name = W.name(root), actions = {} }
end

function O.same(a, b)
    if a.type ~= b.type then
        return false
    elseif a.type == "anim" then
        return a.saveId == b.saveId and math.abs(a.x - b.x) < 1 and math.abs(a.z - b.z) < 1
    end
    return a.uid == b.uid
end

local function key(obj)
    if obj.type == "anim" then
        return string.format("anim:%s@%.0f,%.0f", tostring(obj.saveId), obj.x or 0, obj.z or 0)
    end
    return obj.type .. ":" .. tostring(obj.uid)
end

-- Cíl akcí: vozidlo, obal brány nebo budovy; nil, když objekt ve světě není.
function O.target(obj)
    if obj.type == "vehicle" then
        return W.find(obj.uid)
    elseif obj.type == "anim" then
        local a = O.findAnim(obj.saveId, obj.x or 0, obj.z or 0)
        return a ~= nil and { uniqueId = key(obj), world = true, anim = a } or nil
    elseif obj.type == "placeable" then
        local p = O.findPlaceable(obj.uid)
        return p ~= nil and { uniqueId = key(obj), world = true, placeable = p } or nil
    end
    return nil
end

function O.exists(obj)
    return O.target(obj) ~= nil
end

-- Objekt, jak ho bere CinemaActions (jako herce bez jízdy).
function O.actor(obj)
    return { actions = obj.actions, world = obj.type ~= "vehicle", targets = function()
        local t = O.target(obj)
        return t ~= nil and { t } or {}
    end }
end

-- Poloha objektu ve světě (skok kamery, značka při výběru): x, y, z, nebo nil.
function O.position(obj)
    local t = O.target(obj)
    if t == nil then
        return nil
    elseif t.anim ~= nil then
        return O.animPos(t.anim)
    elseif t.placeable ~= nil then
        return getWorldTranslation(t.placeable.rootNode)
    end
    return getWorldTranslation(t.rootNode)
end

-- Co se u druhu s výběrem (světla, výroba, hadice) dá vybrat: { { sub, label } }.
function O.subs(obj, kind)
    local t = O.target(obj)
    local list = {}
    if t ~= nil and kind == "hose" then
        local spec = O.hoseSpec(t)
        for i, h in ipairs(spec ~= nil and spec.hoses or {}) do
            list[#list + 1] = { sub = i, label = hoseLabel(h, i) }
        end
        return list
    end
    if t == nil or t.placeable == nil then
        return list
    end
    if kind == "lamp" then
        for i, group in ipairs(O.lightGroups(t.placeable) or {}) do
            list[#list + 1] = { sub = i, label = group.name or tostring(i) }
        end
    elseif kind == "production" then
        local pp = O.productionPoint(t.placeable)
        for _, production in ipairs(pp ~= nil and pp.productions or {}) do
            list[#list + 1] = { sub = production.id, label = production.name or tostring(production.id) }
        end
    end
    return list
end

---------------------------------------------------------------------------------------------------
-- výběr T: brány a budovy se světly nebo výrobou pod kurzorem

local function screenPx(sx, sy, mx, my)
    if mx == nil then
        return 0
    end
    return math.sqrt(((sx - mx) / g_pixelSizeScaledX) ^ 2 + ((sy - my) / g_pixelSizeScaledY) ^ 2)
end

-- { anim | placeable, x, y, z, sx, sy, px, name } v dosahu kamery, nejbližší ke kurzoru první.
function O.candidates(cam, mx, my)
    local list = {}
    local function add(c, x, y, z)
        local d = math.sqrt((x - cam.x) ^ 2 + (y - cam.y) ^ 2 + (z - cam.z) ^ 2)
        if d > W.PICK_DISTANCE then
            return
        end
        local sx, sy = CinemaCamera.worldToScreen(cam, x, y, z)
        if sx ~= nil then
            c.sx, c.sy, c.px = sx, sy, screenPx(sx, sy, mx, my)
            list[#list + 1] = c
        end
    end
    for _, a in ipairs(O.animatedObjects()) do
        local x, y, z = O.animPos(a)
        add({ anim = a }, x, y + 1, z)
    end
    for _, p in ipairs(O.placeables()) do
        if p.rootNode ~= nil and (O.lightGroups(p) ~= nil or O.productionPoint(p) ~= nil) then
            local x, y, z = getWorldTranslation(p.rootNode)
            add({ placeable = p }, x, y + 2, z)
        end
    end
    table.sort(list, function(a, b) return a.px < b.px end)
    return list
end

function O.candidateAt(list)
    local c = list[1]
    return c ~= nil and c.px <= O.PICK_PX and c or nil
end

function O.candidateName(c)
    return c.anim ~= nil and O.animName(c.anim) or placeableName(c.placeable)
end

function O.fromCandidate(c)
    return c.anim ~= nil and O.fromAnim(c.anim) or O.fromPlaceable(c.placeable)
end
