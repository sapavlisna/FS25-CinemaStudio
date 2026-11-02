-- Předměty scény: věci, které reset (R, každé Play) postaví na zapamatované místo, i v zapamatované výšce.
-- prop = { kind = "vehicle" | "bale" | "heap" | "field", name, … }:
--   vehicle: start jako u herce (W.captureStart) — palety, bigbagy, nářadí, přívěsy;
--   bale: uid, x, y, z, rx, ry, rz a vlastnosti balíku; zmizelý balík (sebraný, zpracovaný) se vyrobí znovu;
--   heap: fillType (jméno), amount (l), x, z, radius; reset hromadu v okruhu smaže a nasype znovu;
--   field: field (id pole), x, z (kde se stav četl), fruit (jméno plodiny), growth, ground, sprayType, sprayLevel, lime,
--          plow, roller, stubble, weed, stone, water (hodnoty FieldState), clear (1 = smazat řádky a slámu); reset pole
--          nastaví úlohou hry (FieldUpdateTask), která běží několik snímků, a jen když má záběr zapnuté fieldsOn;
--          windrow (druh materiálu řádků), windrowAmount (l/m), windrowLines ("x z x z;…" úseky), windrowSource
--          ("cp" kurz Courseplay | "parallel"), windrowSpacing (m): po doběhnutí úlohy se řádky nasypou po dávkách.
-- Ve hře mění svět jen server (v MP host), jako jízda herců.

CinemaProps = CinemaProps or {}
local Pr = CinemaProps
local W = CinemaWorld

Pr.HEAP_RADIUS = 5 -- m; okruh, ve kterém se hromada měří, maže a sype
Pr.HEAP_RADIUS_MIN = 1
Pr.HEAP_RADIUS_MAX = 20
Pr.BALE_PICK_PX = 40

local function isServer()
    return g_currentMission == nil or g_currentMission:getIsServer()
end

---------------------------------------------------------------------------------------------------
-- balíky

local function baleUid(bale)
    if bale.getUniqueId ~= nil then
        return bale:getUniqueId()
    end
    return bale.uniqueId
end
Pr.baleUid = baleUid

local function usableBale(bale)
    return bale ~= nil and not bale.isDeleted and bale.nodeId ~= nil and bale.nodeId ~= 0 and entityExists(bale.nodeId)
end

-- Všechny balíky ve světě (podle itemSystem, jako EasyDevControls).
function Pr.bales()
    local list = {}
    local system = g_currentMission ~= nil and g_currentMission.itemSystem or nil
    for _, entry in pairs(system ~= nil and system.itemsToSave or {}) do
        local object = type(entry) == "table" and entry.item or nil
        if object ~= nil and object.isa ~= nil and object:isa(Bale) and usableBale(object) then
            list[#list + 1] = object
        end
    end
    return list
end

function Pr.findBale(uid)
    if uid == nil then
        return nil
    end
    for _, bale in ipairs(Pr.bales()) do
        if baleUid(bale) == uid then
            return bale
        end
    end
    return nil
end

local function fillTitle(fillTypeIndex)
    local ft = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeByIndex(fillTypeIndex) or nil
    return ft ~= nil and (ft.title or ft.name) or "?"
end

function Pr.baleName(bale)
    return string.format(g_i18n:getText("cine_prop_bale"), fillTitle(bale.fillType))
end

-- Balíky blízko kurzoru: { bale, sx, sy, dist } nejbližší ke kurzoru první.
function Pr.baleCandidates(cam, mx, my)
    local list = {}
    for _, bale in ipairs(Pr.bales()) do
        local x, y, z = getWorldTranslation(bale.nodeId)
        local d = math.sqrt((x - cam.x) ^ 2 + (y - cam.y) ^ 2 + (z - cam.z) ^ 2)
        if d <= W.PICK_DISTANCE then
            local sx, sy = CinemaCamera.worldToScreen(cam, x, y, z)
            if sx ~= nil then
                local px = mx ~= nil and math.sqrt(((sx - mx) / g_pixelSizeScaledX) ^ 2 + ((sy - my) / g_pixelSizeScaledY) ^ 2) or 0
                list[#list + 1] = { bale = bale, sx = sx, sy = sy, dist = d, px = px }
            end
        end
    end
    table.sort(list, function(a, b) return a.px < b.px end)
    return list
end

function Pr.baleAt(cam, mx, my)
    local c = Pr.baleCandidates(cam, mx, my)[1]
    return c ~= nil and c.px <= Pr.BALE_PICK_PX and c.bale or nil
end

local function readBale(bale)
    local x, y, z = getWorldTranslation(bale.nodeId)
    local rx, ry, rz = getWorldRotation(bale.nodeId)
    local fillTypeName = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeNameByIndex(bale.fillType) or nil
    return {
        uid = baleUid(bale), x = x, y = y, z = z, rx = rx, ry = ry, rz = rz, xmlFilename = bale.xmlFilename,
        fillType = fillTypeName, fillLevel = bale.fillLevel, variation = bale.variationIndex, wrap = bale.wrappingState,
        wrapColor = bale.wrappingColor ~= nil and { bale.wrappingColor[1], bale.wrappingColor[2], bale.wrappingColor[3], bale.wrappingColor[4] } or nil,
        wrapDiffuse = bale.wrapDiffuse, wrapNormal = bale.wrapNormal,
    }
end
Pr.readBale = readBale

local function spawnBale(p)
    if p.xmlFilename == nil then
        return nil
    end
    local mission = g_currentMission
    local bale = Bale.new(mission:getIsServer(), mission:getIsClient())
    if not bale:loadFromConfigXML(p.xmlFilename, p.x, p.y, p.z, p.rx, p.ry, p.rz) then
        bale:delete()
        return nil
    end
    local fillType = p.fillType ~= nil and g_fillTypeManager:getFillTypeIndexByName(p.fillType) or nil
    bale:applyBaleAttributes({ fillType = fillType, fillLevel = p.fillLevel, variationIndex = p.variation,
        wrappingState = p.wrap, wrappingColor = p.wrapColor, wrapDiffuse = p.wrapDiffuse, wrapNormal = p.wrapNormal })
    bale:register()
    return bale
end

local function placeBale(bale, p)
    local qx, qy, qz, qw = mathEulerToQuaternion(p.rx, p.ry, p.rz)
    bale:setWorldPositionQuaternion(p.x, p.y, p.z, qx, qy, qz, qw, true)
    if setLinearVelocity ~= nil then
        setLinearVelocity(bale.nodeId, 0, 0, 0)
        setAngularVelocity(bale.nodeId, 0, 0, 0)
    end
    if bale.wakeUp ~= nil then
        bale:wakeUp()
    end
end
Pr.placeBale = placeBale

---------------------------------------------------------------------------------------------------
-- hromady

local function heapArea(x, z, r)
    return x - r, z - r, x + r, z - r, x - r, z + r
end

-- Hromada pod bodem (x, z): index druhu sypkého materiálu a kolik ho v okruhu r leží (l); nil bez hromady.
function Pr.heapAt(x, z, r)
    if DensityMapHeightUtil == nil then
        return nil
    end
    local y = W.terrainY(x, z)
    local fillType = DensityMapHeightUtil.getFillTypeAtLine(x - 0.5, y, z, x + 0.5, y, z, 1)
    if fillType == nil or fillType == 0 then
        return nil
    end
    local amount = DensityMapHeightUtil.getFillLevelAtArea(fillType, heapArea(x, z, r))
    if amount == nil or amount <= 0 then
        return nil
    end
    return fillType, amount
end

local function tipHeap(p)
    local fillType = g_fillTypeManager:getFillTypeIndexByName(p.fillType)
    if fillType == nil then
        return false, "propMissing"
    end
    local r = p.radius or Pr.HEAP_RADIUS
    local sx, sz, wx, wz, hx, hz = heapArea(p.x, p.z, r)
    DensityMapHeightUtil.removeFromGroundByArea(sx, sz, wx, wz, hx, hz, fillType)
    local y = W.terrainY(p.x, p.z)
    local left = p.amount
    -- jedno sypnutí se nemusí vejít (svah, okruh): zbytek do širšího
    for k = 1, 8 do
        local dropped = DensityMapHeightUtil.tipToGroundAroundLine(nil, left, fillType, p.x - 0.5, y, p.z, p.x + 0.5, y, p.z,
            0, r * (0.4 + 0.15 * k), nil, false, nil, false)
        left = left - (dropped or 0)
        if left <= 1 then
            break
        end
    end
    return true
end

---------------------------------------------------------------------------------------------------
-- pole

Pr.FIELD_WAIT_MAX = 30000 -- ms; déle se na úlohu pole nečeká (přehrání by jinak viselo)
Pr.fieldTasks = {}

-- prop klíč → položka FieldState
Pr.FIELD_STATE = { growth = "growthState", ground = "groundType", sprayType = "sprayType", sprayLevel = "sprayLevel",
    lime = "limeLevel", plow = "plowLevel", roller = "rollerLevel", stubble = "stubbleShredLevel", weed = "weedState",
    stone = "stoneLevel", water = "waterLevel" }

local function insidePolygon(points, x, z)
    local inside = false
    local n = #points
    local j = n
    for i = 1, n do
        local xi, zi = points[i][1], points[i][2]
        local xj, zj = points[j][1], points[j][2]
        if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi then
            inside = not inside
        end
        j = i
    end
    return inside
end
Pr.insidePolygon = insidePolygon

local function fields()
    return g_fieldManager ~= nil and g_fieldManager:getFields() or {}
end

-- Pole, do kterého padne bod (x, z), nebo nil.
function Pr.fieldAt(x, z)
    for _, field in ipairs(fields()) do
        local points = {}
        for _, node in ipairs(field:getPolygonPoints() or {}) do
            local px, _, pz = getWorldTranslation(node)
            points[#points + 1] = { px, pz }
        end
        if #points >= 3 and insidePolygon(points, x, z) then
            return field
        end
    end
    return nil
end

function Pr.findField(id)
    return id ~= nil and g_fieldManager ~= nil and g_fieldManager:getFieldById(id) or nil
end

function Pr.fieldName(field)
    local name = field.getName ~= nil and field:getName() or nil
    if name == nil or name == "" then
        name = string.format(g_i18n:getText("cine_field_name"), field:getId())
    end
    return name
end

-- Stav pole v bodě (x, z) do předmětu p; false, když tam hra platný stav nemá.
local function readField(p, x, z)
    local fs = FieldState.new()
    fs:update(x, z)
    if not fs.isValid then
        return false
    end
    local ft = fs.fruitTypeIndex ~= FruitType.UNKNOWN and g_fruitTypeManager:getFruitTypeByIndex(fs.fruitTypeIndex) or nil
    p.fruit = ft ~= nil and ft.name or nil
    for key, name in pairs(Pr.FIELD_STATE) do
        p[key] = fs[name]
    end
    p.x, p.z = x, z
    return true
end

-- Pole pod bodem (x, z) jako předmět se stavem, který tam teď je; nil mimo pole.
function Pr.fromField(x, z)
    local field = Pr.fieldAt(x, z)
    if field == nil then
        return nil
    end
    local p = { kind = "field", field = field:getId(), name = Pr.fieldName(field), clear = 1 }
    if not readField(p, x, z) then
        return nil
    end
    return p
end

function Pr.fruitOf(p)
    return p.fruit ~= nil and g_fruitTypeManager:getFruitTypeByName(p.fruit) or nil
end

---------------------------------------------------------------------------------------------------
-- řádky (sláma, tráva, seno) po sklizni

Pr.WINDROW_TYPES = { "STRAW", "GRASS_WINDROW", "DRYGRASS_WINDROW", "ALFALFA_WINDROW", "DRYALFALFA_WINDROW" }
Pr.WINDROW_AMOUNT = 40 -- l/m
Pr.WINDROW_AMOUNT_STEP = 10
Pr.WINDROW_AMOUNT_MAX = 300
Pr.WINDROW_SPACING = 9 -- m; rovnoběžné řádky bez kurzu
Pr.WINDROW_SPACING_MIN = 3
Pr.WINDROW_SPACING_MAX = 24
Pr.WINDROW_RADIUS = 0.7 -- m; jak široko se řádek sype kolem čáry
Pr.WINDROW_CHUNK = 4 -- m; délka jednoho sypnutí (rovnoměrný řádek)
Pr.WINDROW_PER_FRAME = 60 -- sypnutí za snímek

-- Druhy řádků, které hra zná: { name, title }.
function Pr.windrowTypes()
    local list = {}
    for _, name in ipairs(Pr.WINDROW_TYPES) do
        local index = g_fillTypeManager:getFillTypeIndexByName(name)
        local ft = index ~= nil and g_fillTypeManager:getFillTypeByIndex(index) or nil
        if ft ~= nil then
            list[#list + 1] = { name = name, title = ft.title or name }
        end
    end
    return list
end

function Pr.encodeLines(lines)
    local parts = {}
    for _, l in ipairs(lines) do
        parts[#parts + 1] = string.format("%.1f %.1f %.1f %.1f", l[1], l[2], l[3], l[4])
    end
    return table.concat(parts, ";")
end

function Pr.decodeLines(text)
    local lines = {}
    for part in string.gmatch(text or "", "[^;]+") do
        local a, b, c, d = part:match("^%s*(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
        if d ~= nil then
            lines[#lines + 1] = { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
        end
    end
    return lines
end

function Pr.fieldPolygon(field)
    local points = {}
    for _, node in ipairs(field:getPolygonPoints() or {}) do
        local x, _, z = getWorldTranslation(node)
        points[#points + 1] = { x, z }
    end
    return points
end

-- Rovnoběžné řádky přes polygon po spacing metrech, podél nejdelší hrany: { { x1, z1, x2, z2 }, … }.
function Pr.parallelLines(points, spacing)
    local n = #points
    if n < 3 then
        return {}
    end
    local best, dx, dz = -1, 1, 0
    for i = 1, n do
        local a, b = points[i], points[i % n + 1]
        local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
        if len > best then
            best, dx, dz = len, (b[1] - a[1]) / len, (b[2] - a[2]) / len
        end
    end
    local nx, nz = -dz, dx
    local lo, hi = math.huge, -math.huge
    for _, p in ipairs(points) do
        local d = p[1] * nx + p[2] * nz
        lo, hi = math.min(lo, d), math.max(hi, d)
    end
    local lines = {}
    local o = lo + spacing * 0.5
    while o < hi do
        local hits = {}
        for i = 1, n do
            local a, b = points[i], points[i % n + 1]
            local da, db = a[1] * nx + a[2] * nz - o, b[1] * nx + b[2] * nz - o
            if (da < 0) ~= (db < 0) then
                local t = da / (da - db)
                local x, z = a[1] + t * (b[1] - a[1]), a[2] + t * (b[2] - a[2])
                hits[#hits + 1] = { x, z, x * dx + z * dz }
            end
        end
        table.sort(hits, function(p, q) return p[3] < q[3] end)
        for k = 1, #hits - 1, 2 do
            lines[#lines + 1] = { hits[k][1], hits[k][2], hits[k + 1][1], hits[k + 1][2] }
        end
        o = o + spacing
    end
    return lines
end

-- Úseky kurzu Courseplay uvnitř polygonu (body řádků a průjezdy souvratí, obraty ne): lines, jméno, pracovní šířka.
local function courseSegments(course, points)
    local wps = course.getAllWaypoints ~= nil and course:getAllWaypoints() or nil
    if wps == nil then
        return nil
    end
    local lines, inRow = {}, false
    local prev = nil
    for i = 1, #wps do
        local wp = wps[i]
        local x, _, z = wp:getPosition()
        local attrs = wp.attributes or {}
        local onHeadland = (attrs.headlandPassNumber or 0) > 0
        -- úsek patří řádku, když v něm byl už předchozí bod (obrat mezi řádky ne)
        if prev ~= nil and (inRow or (onHeadland and prev.headland)) then
            local mx, mz = (prev.x + x) * 0.5, (prev.z + z) * 0.5
            if insidePolygon(points, mx, mz) then
                lines[#lines + 1] = { prev.x, prev.z, x, z }
            end
        end
        if wp:isRowEnd() then
            inRow = false
        end
        if wp:isRowStart() then
            inRow = true
        end
        prev = { x = x, z = z, headland = onHeadland }
    end
    return lines, course.getName ~= nil and course:getName() or nil, course.getWorkWidth ~= nil and course:getWorkWidth() or nil
end

-- Řádky z kurzu Courseplay, který má některý stroj ve hře načtený pro toto pole (jen úseky uvnitř pole): lines, jméno
-- kurzu, pracovní šířka; nil bez kurzu. Volání Courseplay jsou v pcall (jiná verze nesmí shodit editor).
function Pr.courseLines(field)
    local points = Pr.fieldPolygon(field)
    local best, bestCount, bestName, bestWidth = nil, 0, nil, nil
    for _, v in ipairs(W.vehicles()) do
        local okCourse, course = pcall(function() return v.getFieldWorkCourse ~= nil and v:getFieldWorkCourse() or nil end)
        local ok, lines, name, width = false, nil, nil, nil
        if okCourse and type(course) == "table" then
            ok, lines, name, width = pcall(courseSegments, course, points)
        end
        if ok and lines ~= nil and #lines > bestCount then
            best, bestCount, bestName, bestWidth = lines, #lines, name, width
        end
    end
    return best, bestName, bestWidth
end

-- Úseky řádků rozdělené na krátká sypnutí: { { sx, sz, ex, ez, liters }, … }.
local function windrowChunks(p)
    local chunks = {}
    local amount = p.windrowAmount or Pr.WINDROW_AMOUNT
    for _, l in ipairs(Pr.decodeLines(p.windrowLines)) do
        local len = math.sqrt((l[3] - l[1]) ^ 2 + (l[4] - l[2]) ^ 2)
        local n = math.max(1, math.ceil(len / Pr.WINDROW_CHUNK))
        for k = 0, n - 1 do
            local t0, t1 = k / n, (k + 1) / n
            chunks[#chunks + 1] = { l[1] + (l[3] - l[1]) * t0, l[2] + (l[4] - l[2]) * t0, l[1] + (l[3] - l[1]) * t1,
                l[2] + (l[4] - l[2]) * t1, amount * len / n }
        end
    end
    return chunks
end

local function tipChunk(fillType, c)
    local sy, ey = W.terrainY(c[1], c[2]), W.terrainY(c[3], c[4])
    DensityMapHeightUtil.tipToGroundAroundLine(nil, c[5], fillType, c[1], sy, c[2], c[3], ey, c[4], 0, Pr.WINDROW_RADIUS, nil,
        false, nil, false)
end

local function applyField(p)
    local field = Pr.findField(p.field)
    if field == nil then
        return false, "propMissing"
    end
    local fs = FieldState.new()
    fs.isValid = true
    local ft = Pr.fruitOf(p)
    fs.fruitTypeIndex = ft ~= nil and ft.index or FruitType.UNKNOWN
    for key, name in pairs(Pr.FIELD_STATE) do
        if p[key] ~= nil then
            fs[name] = p[key]
        end
    end
    local task = fs:createFieldUpdateTask()
    task:setField(field)
    if p.clear ~= 0 then
        task:clearHeight()
    end
    g_fieldManager:addFieldUpdateTask(task)
    local entry = { task = task, since = g_time }
    local fillType = p.windrow ~= nil and g_fillTypeManager:getFillTypeIndexByName(p.windrow) or nil
    if fillType ~= nil and DensityMapHeightUtil ~= nil then
        entry.fillType, entry.chunks, entry.next = fillType, windrowChunks(p), 1
    end
    Pr.fieldTasks[#Pr.fieldTasks + 1] = entry
    return true
end

-- Krok nastavování polí (každý snímek editoru): po doběhnutí úlohy pole nasype po dávkách jeho řádky.
function Pr.updateFields()
    for _, entry in ipairs(Pr.fieldTasks) do
        if entry.chunks ~= nil and entry.next <= #entry.chunks and entry.task:getIsFinished() then
            local last = math.min(entry.next + Pr.WINDROW_PER_FRAME - 1, #entry.chunks)
            for k = entry.next, last do
                tipChunk(entry.fillType, entry.chunks[k])
            end
            entry.next = last + 1
        end
    end
end

-- Běží ještě úloha, která nastavuje pole? Přehrávání na ni počká (nejvýš FIELD_WAIT_MAX).
function Pr.fieldsBusy()
    local keep = {}
    for _, entry in ipairs(Pr.fieldTasks) do
        if not entry.task:getIsFinished() or (entry.chunks ~= nil and entry.next <= #entry.chunks) then
            if g_time - entry.since < Pr.FIELD_WAIT_MAX then
                keep[#keep + 1] = entry
            else
                Logging.warning("CinemaStudio: setting the field takes longer than %d s, playback does not wait", Pr.FIELD_WAIT_MAX / 1000)
            end
        end
    end
    Pr.fieldTasks = keep
    return #keep > 0
end

---------------------------------------------------------------------------------------------------
-- zapamatování a reset

---------------------------------------------------------------------------------------------------
-- předmět na vozidle (big bag na vleku, balíky na návěsu, paleta na korbě): když při zapamatování leží na jiném vozidle,
-- pamatuje si ho (rider, lx, ly, lz, lry) a celý záběr s ním jede napevno, bez fyziky (nesklouzne); reset ho postaví zpátky
-- na vozidlo. Souprava (víc článků) se nevozí. Předmět, který v záběru nese postava, vozí akce nesení.

local function propObject(p)
    if p.kind == "vehicle" then
        local e = p.start ~= nil and p.start.entries[1] or nil
        local v = e ~= nil and W.find(e.uid) or nil
        return v ~= nil and v.rootNode or nil, v, nil, e ~= nil and e.uid or nil
    elseif p.kind == "bale" then
        local bale = Pr.findBale(p.uid)
        return bale ~= nil and bale.nodeId or nil, nil, bale, p.uid
    end
    return nil
end

function Pr.captureRider(p)
    local node, v, bale = propObject(p)
    local attached = v ~= nil and v.getAttacherVehicle ~= nil and v:getAttacherVehicle() ~= nil
    if node == nil or attached or (p.kind == "vehicle" and #p.start.entries > 1) then
        p.rider = nil
        return
    end
    local area
    if v ~= nil then
        area = (v.size ~= nil and v.size.width or 1) * (v.size ~= nil and v.size.length or 1)
    else
        area = (bale.width or bale.diameter or 1.2) * (bale.length or bale.diameter or 1.2)
    end
    W.captureRider(p, v, node, area)
end

-- předmět → { vehicle | bale }: jede s vozidlem, je vyjmutý z fyziky (vozidlo) nebo kinematický (balík)
Pr.riding = {}

local function hold(r, on)
    if r.vehicle ~= nil and not r.vehicle.isDeleted then
        if on then
            r.vehicle:removeFromPhysics()
        else
            r.vehicle:addToPhysics()
        end
    elseif r.bale ~= nil and r.bale.nodeId ~= nil and setRigidBodyType ~= nil and RigidBodyType ~= nil and entityExists(r.bale.nodeId) then
        setRigidBodyType(r.bale.nodeId, on and RigidBodyType.KINEMATIC or RigidBodyType.DYNAMIC)
    end
end

local function release(p)
    local r = Pr.riding[p]
    Pr.riding[p] = nil
    if r ~= nil then
        hold(r, false)
    end
end

-- Každý snímek editoru (po pohybu vozidel): předměty na vozidlech jedou s nimi. skip = uid vozidel, která nese postava.
function Pr.syncRiders(props, skip)
    local seen = {}
    for _, p in ipairs(props) do
        if p.rider ~= nil then
            local node, v, bale, uid = propObject(p)
            local x, y, z, ry = W.ridePose(p)
            if node ~= nil and x ~= nil and not (skip ~= nil and uid ~= nil and skip[uid]) then
                seen[p] = true
                local r = Pr.riding[p]
                if r == nil then
                    r = { vehicle = v, bale = bale }
                    Pr.riding[p] = r
                    hold(r, true)
                end
                if v ~= nil then
                    local e = p.start.entries[1]
                    v:setAbsolutePosition(x, y, z, e.rx, ry, e.rz)
                else
                    placeBale(bale, { x = x, y = y, z = z, rx = p.rx, ry = ry, rz = p.rz })
                end
            end
        end
    end
    for p in pairs(Pr.riding) do
        if not seen[p] then
            release(p)
        end
    end
end

-- Editor se zavírá: předměty na vozidlech zase s fyzikou, kde právě jsou.
function Pr.releaseRiders()
    for p in pairs(Pr.riding) do
        release(p)
    end
end

function Pr.fromVehicle(v)
    local root = W.rootOf(v)
    local p = { kind = "vehicle", name = W.name(root), start = W.captureStart(root) }
    Pr.captureRider(p)
    return p
end

function Pr.fromBale(bale)
    local p = readBale(bale)
    p.kind, p.name = "bale", Pr.baleName(bale)
    Pr.captureRider(p)
    return p
end

function Pr.heapName(p)
    local fillType = g_fillTypeManager:getFillTypeIndexByName(p.fillType)
    return string.format(g_i18n:getText("cine_prop_heap"), fillTitle(fillType), p.amount / 1000)
end

-- Hromada pod bodem (x, z) jako předmět; nil, když tam žádná není.
function Pr.fromHeap(x, z, r)
    r = r or Pr.HEAP_RADIUS
    local fillType, amount = Pr.heapAt(x, z, r)
    if fillType == nil then
        return nil
    end
    local p = { kind = "heap", fillType = g_fillTypeManager:getFillTypeNameByIndex(fillType), amount = amount, x = x, z = z, radius = r }
    p.name = Pr.heapName(p)
    return p
end

-- Zapamatuje si současný stav ve světě (poloha vozidla nebo balíku, množství hromady). false, když věc chybí.
function Pr.recapture(p)
    if p.kind == "vehicle" then
        local root = p.start ~= nil and p.start.entries[1] ~= nil and W.find(p.start.entries[1].uid) or nil
        if root == nil then
            return false
        end
        p.start = W.captureStart(root)
        Pr.captureRider(p)
    elseif p.kind == "bale" then
        local bale = Pr.findBale(p.uid)
        if bale == nil then
            return false
        end
        local fresh = readBale(bale)
        for k, v in pairs(fresh) do
            p[k] = v
        end
        Pr.captureRider(p)
    elseif p.kind == "heap" then
        local fillType, amount = Pr.heapAt(p.x, p.z, p.radius or Pr.HEAP_RADIUS)
        if fillType == nil then
            return false
        end
        p.fillType, p.amount = g_fillTypeManager:getFillTypeNameByIndex(fillType), amount
        p.name = Pr.heapName(p)
    elseif p.kind == "field" then
        return Pr.findField(p.field) ~= nil and readField(p, p.x, p.z)
    end
    return true
end

-- Existuje věc ve světě (hromada se dá nasypat vždy)?
function Pr.exists(p)
    if p.kind == "vehicle" then
        return p.start ~= nil and p.start.entries[1] ~= nil and W.find(p.start.entries[1].uid) ~= nil
    elseif p.kind == "bale" then
        return Pr.findBale(p.uid) ~= nil
    elseif p.kind == "field" then
        return Pr.findField(p.field) ~= nil
    end
    return true
end

-- Postaví předmět na zapamatované místo. Vrací true (changed = true, když vznikl nový balík s jiným uid), nebo false a důvod.
function Pr.reset(p)
    if not isServer() then
        return false, "notServer"
    end
    -- reset vrátí fyziku; předmět na vozidle ji další snímek zase vypne a postaví ho na vozidlo
    Pr.riding[p] = nil
    if p.kind == "vehicle" then
        return W.resetStart(p.start)
    elseif p.kind == "bale" then
        local bale = Pr.findBale(p.uid)
        if bale ~= nil then
            placeBale(bale, p)
            return true
        end
        bale = spawnBale(p)
        if bale == nil then
            return false, "propMissing"
        end
        p.uid = baleUid(bale)
        return true, true
    elseif p.kind == "heap" then
        return tipHeap(p)
    elseif p.kind == "field" then
        return applyField(p)
    end
    return false, "propMissing"
end

-- Poloha předmětu ve světě (pro náhled a skok kamery): x, y, z.
function Pr.position(p)
    if p.kind == "vehicle" then
        local e = p.start ~= nil and p.start.entries[1] or nil
        if e ~= nil then
            return e.x, e.y, e.z
        end
        return nil
    elseif p.kind == "bale" then
        return p.x, p.y, p.z
    end
    return p.x, W.terrainY(p.x, p.z), p.z
end

-- Posun zapamatované výšky o dy (m): vozidlo celé, balík; hromada leží vždy na terénu.
function Pr.raise(p, dy)
    if p.kind == "vehicle" then
        for _, e in ipairs(p.start ~= nil and p.start.entries or {}) do
            e.y = e.y + dy
        end
        return true
    elseif p.kind == "bale" then
        p.y = p.y + dy
        return true
    end
    return false
end
