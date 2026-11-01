-- Postava v záběru (docs/PLAN-postava.md): herec s actor.person = "player" je hráč sám. Chodí po trase herce (body jako
-- u vozidla, bod může mít natočení p[6]), při přehrávání se mu každý snímek dosadí vstup, jako by držel klávesy
-- (ověřeno sondou ve hře). Start: actor.start.person = { x, y, z, yaw }.
-- actor.person = "helper" je pomocník (actor.helper = jméno z HelperManageru): jen model bez fyziky, který stojí přesně
-- tam, kde ho trasa v čase osy chce mít, i mimo přehrávání.
-- Akce postavy (CinemaActions, druhy seat a door): nástup do vozidla a výstup, otevření a zavření animace vozidla.

CinemaPerson = CinemaPerson or {}
local Pe = CinemaPerson
local R = CinemaRoute
local M = CinemaMath

Pe.PLAYER = "player"
Pe.HELPER = "helper"
-- Postava jde pomalu, jde, nebo běží; stát = pauza v bodě trasy. Hráč ve hře má plný krok 4 m/s a běh 7 m/s
-- (PlayerStateWalk.MAXIMUM_WALK_SPEED / MAXIMUM_RUN_SPEED, přečteno ve hře), ale model pomocníka při 4 m/s hraje běh
-- (animace podle absSpeed), takže chůze je 1,5 m/s (při 5 km/h ve hře viditelně šel) a běh jako ve hře.
Pe.GAME_WALK_MPS = 4
Pe.SLOW_MPS = 0.9
Pe.WALK_MPS = 1.5
Pe.RUN_MPS = 7
Pe.SLOW_KMH = Pe.SLOW_MPS * 3.6
Pe.WALK_KMH = Pe.WALK_MPS * 3.6
Pe.RUN_KMH = Pe.RUN_MPS * 3.6
Pe.GAITS = { { name = "slow", kmh = Pe.SLOW_KMH }, { name = "walk", kmh = Pe.WALK_KMH }, { name = "run", kmh = Pe.RUN_KMH } }
Pe.CATCH_UP = 1.5 -- 1/s; jak rychle postava dohání plánovanou polohu
Pe.TURN_RATE = math.pi -- rad/s; otáčení na místě
Pe.IDLE_MPS = 0.15

-- Vstup, který hook dosadí hráči v tomto snímku: { dirX, dirZ, axis } nebo nil.
Pe.feed = nil

function Pe.isPerson(actor)
    return actor ~= nil and actor.person ~= nil
end

function Pe.isHelper(actor)
    return actor ~= nil and actor.person == Pe.HELPER
end

local function player()
    return g_localPlayer
end

function Pe.playerYaw()
    local p = player()
    if p == nil then
        return 0
    end
    if p.getMovementYaw ~= nil then
        return p:getMovementYaw()
    end
    return p.mover ~= nil and p.mover.movementDirectionYaw or 0
end

-- Poloha hráče na zemi (x, y, z); ve vozidle u vozidla.
function Pe.playerPos()
    local p = player()
    if p == nil then
        return 0, 0, 0
    end
    return p:getPosition()
end

function Pe.captureStart()
    local x, y, z = Pe.playerPos()
    return { entries = {}, joints = {}, person = { x = x, y = y, z = z, yaw = Pe.playerYaw() } }
end

function Pe.newActor(name)
    local start = Pe.captureStart()
    return { person = Pe.PLAYER, name = name, speed = Pe.WALK_KMH, delay = 0, points = { { start.person.x, start.person.z } },
        start = start, actions = {} }
end

-- Pomocník „Já“: model se vzhledem hráče, chodí s animací jako ostatní pomocníci (hráč sám se při přehrávání jen posouvá).
Pe.SELF = "cinemaSelf"

-- Z koho jde pomocník udělat: „Já“ a pomocníci HelperManageru se vzhledem. { name, title }.
function Pe.helperChoices()
    local list = { { name = Pe.SELF, title = g_i18n:getText("cine_person_self") } }
    for _, helper in ipairs(CinemaWorld.helperList()) do
        if helper.playerStyle ~= nil then
            list[#list + 1] = { name = helper.name, title = helper.title or helper.name }
        end
    end
    return list
end

function Pe.helperTitle(name)
    for _, choice in ipairs(Pe.helperChoices()) do
        if choice.name == name then
            return choice.title
        end
    end
    return "?"
end

-- Vzhled pomocníka podle jména; u „Já“ kopie současného vzhledu hráče (nil, když hráč není).
function Pe.styleOf(name)
    if name == Pe.SELF then
        local p = player()
        local gc = p ~= nil and p.graphicsComponent or nil
        if gc == nil or gc.getStyle == nil or PlayerStyle == nil then
            return nil
        end
        local ok, style = pcall(function()
            local copy = PlayerStyle.new()
            copy:copyFrom(gc:getStyle(true))
            return copy
        end)
        return ok and style or nil
    end
    local helper = g_helperManager ~= nil and name ~= nil and g_helperManager:getHelperByName(name) or nil
    return helper ~= nil and helper.playerStyle or nil
end

-- Vlastní vzhled pomocníka přes vzhled z HelperManageru: actor.look = { [konfigurace] = { item = jméno kusu ("" = nic),
-- color = index barvy } }. Konfigurace vanilla PlayerStyle v pořadí, jak se nabízejí.
Pe.LOOK_CONFIGS = { "face", "hairStyle", "beard", "headgear", "glasses", "facegear", "top", "bottom", "onepiece", "gloves", "footwear" }

-- Otisk vzhledu herce: když se změní, model pomocníka se postaví znovu.
function Pe.lookKey(actor)
    local parts = { tostring(actor.helper) }
    for _, name in ipairs(Pe.LOOK_CONFIGS) do
        local part = actor.look ~= nil and actor.look[name] or nil
        if part ~= nil then
            parts[#parts + 1] = string.format("%s=%s/%s", name, tostring(part.item), tostring(part.color))
        end
    end
    return table.concat(parts, ";")
end

-- Kopie vzhledu pomocníka (nebo hráče u „Já“) s kusy z actor.look; nil, když vzhled není.
local function styledCopy(actor)
    local baseStyle = Pe.styleOf(actor.helper)
    if baseStyle == nil or PlayerStyle == nil then
        return nil
    end
    local ok, style = pcall(function()
        local copy = PlayerStyle.new()
        copy:copyFrom(baseStyle)
        if copy.loadConfigurationIfRequired ~= nil then
            copy:loadConfigurationIfRequired()
        end
        for name, part in pairs(actor.look or {}) do
            local config = copy.configs[name]
            if config ~= nil then
                if part.item == "" then
                    config:setSelectedItemIndex(0)
                elseif part.item ~= nil then
                    config:setSelectedItemName(part.item)
                end
                if part.color ~= nil then
                    config:setSelectedColorIndex(part.color)
                end
            end
        end
        return copy
    end)
    return ok and style or nil
end

-- Vzhled herce-pomocníka: vzhled pomocníka (nebo hráče u „Já“) s kusy z actor.look.
function Pe.actorStyle(actor)
    if actor.look == nil or next(actor.look) == nil then
        return Pe.styleOf(actor.helper)
    end
    return styledCopy(actor) or Pe.styleOf(actor.helper)
end

-- Šatník hry pro pomocníka: šatník umí oblékat jen hráče, takže hráč dočasně dostane vzhled herce, šatník se otevře a po
-- jeho zavření (Pe.wardrobeClosed) se výsledek zapíše do actor.look a hráč dostane zpět svůj vzhled, i uložený „poslední
-- vzhled“ v nastavení hry a ve hráčových datech savu. Editor se otevře znovu v dalším snímku (Pe.reopenEditor).
Pe.wardrobe = nil

local function copyStyle(style)
    if style == nil or PlayerStyle == nil then
        return nil
    end
    local copy = PlayerStyle.new()
    copy:copyFrom(style)
    return copy
end

local function playerData(p)
    local system = g_currentMission ~= nil and g_currentMission.playerSystem or nil
    if system == nil or system.getPlayerDataByUniqueId == nil or p.uniqueUserId == nil then
        return nil
    end
    return system:getPlayerDataByUniqueId(p.uniqueUserId)
end

-- Kusy a barvy všech konfigurací vzhledu jako actor.look.
local function lookOf(style)
    local look = {}
    for _, name in ipairs(Pe.LOOK_CONFIGS) do
        local config = style ~= nil and style.configs ~= nil and style.configs[name] or nil
        if config ~= nil and config.items ~= nil then
            local index = config.selectedItemIndex or 0
            local item = config.items[index]
            look[name] = { item = index == 0 and "" or (item ~= nil and item.name or nil), color = config.selectedColorIndex }
        end
    end
    return look
end

function Pe.canWardrobe(actor)
    local p = player()
    return Pe.isHelper(actor) and actor.helper ~= Pe.SELF and WardrobeScreen ~= nil and g_gui ~= nil and g_gui.changeScreen ~= nil
        and p ~= nil and p.setStyleAsync ~= nil and p.graphicsComponent ~= nil and p.graphicsComponent.getStyle ~= nil
end

function Pe.openWardrobe(actor)
    if not Pe.canWardrobe(actor) then
        return false
    end
    local p = player()
    local ok = pcall(function()
        local wear = copyStyle(Pe.actorStyle(actor))
        local data = playerData(p)
        Pe.wardrobe = { actor = actor, own = copyStyle(p.graphicsComponent:getStyle(true)),
            last = g_gameSettings ~= nil and copyStyle(g_gameSettings.lastPlayerStyle) or nil,
            data = data, dataStyle = data ~= nil and copyStyle(data.style) or nil }
        p:setStyleAsync(wear, false, nil, true)
        g_gui:changeScreen(nil, WardrobeScreen)
    end)
    if not ok then
        Pe.wardrobeClosed(true)
    end
    return ok
end

-- Zavřený šatník: vzhled pro herce (kromě zrušení), vlastní vzhled zpět hráči.
function Pe.wardrobeClosed(cancel)
    local w = Pe.wardrobe
    if w == nil then
        return
    end
    Pe.wardrobe = nil
    local p = player()
    if not cancel then
        pcall(function() w.actor.look = lookOf(p.graphicsComponent:getStyle(true)) end)
    end
    pcall(function()
        p:setStyleAsync(copyStyle(w.own), false, nil, true)
        if PlayerSetStyleEvent ~= nil and PlayerSetStyleEvent.sendEvent ~= nil then
            PlayerSetStyleEvent.sendEvent(p, w.own)
        end
    end)
    if g_gameSettings ~= nil and w.last ~= nil then
        g_gameSettings.lastPlayerStyle = w.last
    end
    if w.data ~= nil then
        w.data.style = w.dataStyle
    end
    Pe.reopenEditor = true
end

if WardrobeScreen ~= nil and WardrobeScreen.onClose ~= nil and not WardrobeScreen.cinemaStudioHooked then
    WardrobeScreen.cinemaStudioHooked = true
    WardrobeScreen.onClose = Utils.appendedFunction(WardrobeScreen.onClose, function() CinemaPerson.wardrobeClosed() end)
end

-- Pomocník (helper = { name, title }, položka HelperManageru nebo „Já“) stojí na x, z natočený yaw.
function Pe.newHelperActor(helper, x, z, yaw)
    local y = CinemaWorld.terrainY(x, z)
    return { person = Pe.HELPER, helper = helper.name, name = helper.title or helper.name, speed = Pe.WALK_KMH, delay = 0,
        points = { { x, z } }, start = { entries = {}, joints = {}, person = { x = x, y = y, z = z, yaw = yaw } }, actions = {} }
end

-- Azimut jako na mapě (0° sever = -z, 90° východ = +x) z natočení yaw = atan2(dx, dz) a zpět.
function Pe.azimuth(yaw)
    return (180 - math.deg(yaw)) % 360
end

function Pe.yawOfAzimuth(deg)
    return math.rad(180 - deg)
end

-- Nástup a výstup podle akcí na ose v čase t (s od začátku záběru): nil, dokud postava do ničeho nenastoupila, jinak
-- { inside, vehicle } podle poslední akce do t (vehicle = uid vozidla, do kterého naposledy nastoupila).
function Pe.seatAt(actor, t)
    local tLocal = t - (actor.delay or 0)
    local state = nil
    for _, e in ipairs(CinemaActions.events(actor)) do
        if e.t > tLocal + 1e-6 then
            break
        end
        if e.kind == "seat" then
            if e.value == 1 and e.vehicle ~= nil then
                state = { inside = true, vehicle = e.vehicle }
            elseif state ~= nil then
                state = { inside = false, vehicle = state.vehicle }
            end
        end
    end
    return state
end

-- Výstupy z vozidla v pořadí času: { t (s od začátku záběru), vehicle (uid), leg (id části trasy) }; výstup bez nástupu se
-- nepočítá.
function Pe.exits(actor)
    local list, inside = {}, nil
    for _, e in ipairs(CinemaActions.events(actor)) do
        if e.kind == "seat" then
            if e.value == 1 and e.vehicle ~= nil then
                inside = e.vehicle
            elseif inside ~= nil then
                list[#list + 1] = { t = (actor.delay or 0) + e.t, vehicle = inside, leg = e.leg }
                inside = nil
            end
        end
    end
    return list
end

-- Id části trasy (od 2; 1 je část od startu): nese ho akce, ze které výstup vzniká (action.leg), bod výstupu (p[7]) i křivka
-- rychlosti části, takže se body a křivka drží svého výstupu, i když se akce přesunou, smažou nebo přibude další nástup.
-- Akce bez id (nová, vložená kopie) dostane nové; bod jen s p[7] = true (starý zápis) id výstupu podle pořadí.
function Pe.assignLegIds(actor)
    local top, seen, changed = 1, {}, false
    for _, p in ipairs(actor.points or {}) do
        if type(p[7]) == "number" then
            top = math.max(top, p[7])
        end
    end
    for _, action in ipairs(actor.actions or {}) do
        top = math.max(top, action.leg or 0)
    end
    for _, action in ipairs(actor.actions or {}) do
        if action.kind == "seat" and (action.value == 0 or action.dur ~= nil) then
            if action.leg == nil or seen[action.leg] then
                top = top + 1
                action.leg, changed = top, true
            end
            seen[action.leg] = true
        end
    end
    local exits, k = nil, 0
    for j = 2, #(actor.points or {}) do
        local p = actor.points[j]
        if p[7] == true then
            exits = exits or Pe.exits(actor)
            k = k + 1
            if exits[k] ~= nil and exits[k].leg ~= nil then
                p[7] = exits[k].leg
            else
                top = top + 1
                p[7] = top
            end
            changed = true
        end
    end
    return changed
end

-- Trasa postavy po částech: bod s p[7] (výstup z vozidla) začíná další část, která se jde od výstupu s id p[7].
-- { id, from, to (indexy bodů), start (s od začátku záběru; nil, když výstup na ose chybí), vehicle, actor (herec části pro
-- R.plan) }. Část bez výstupu na ose se nejde, ale body si drží, dokud se výstup nevrátí (přesun akce, zpět).
local legActors = setmetatable({}, { __mode = "k" })

-- Index chůze v Pe.GAITS nejbližší rychlosti kmh (nil = chůze).
function Pe.gaitIndex(kmh)
    local best, bestD = 2, math.huge
    for k, gait in ipairs(Pe.GAITS) do
        local d = math.abs((kmh or Pe.WALK_KMH) - gait.kmh)
        if d < bestD then
            best, bestD = k, d
        end
    end
    return best
end

-- Rychlost úseku za bodem p po posunu o dir chůzí (kolem dokola); chůze = nil, ta je výchozí.
function Pe.stepGait(p, dir)
    local gait = Pe.GAITS[(Pe.gaitIndex(p[3]) - 1 + dir) % #Pe.GAITS + 1]
    p[3] = gait.name ~= "walk" and gait.kmh or nil
end

function Pe.gaitTitle(kmh)
    return g_i18n:getText("cine_gait_" .. Pe.GAITS[Pe.gaitIndex(kmh)].name)
end

-- Rychlosti postavy přichytí na pomalou chůzi, chůzi a běh (vždy od bodu do dalšího) a zahodí křivky rychlosti.
function Pe.snapGaits(actor)
    actor.speed = Pe.WALK_KMH
    for _, p in ipairs(actor.points or {}) do
        if p[3] ~= nil then
            local gait = Pe.GAITS[Pe.gaitIndex(p[3])]
            p[3] = gait.name ~= "walk" and gait.kmh or nil
        end
    end
    for id in pairs(actor.curves or {}) do
        if id:sub(1, 5) == "speed" then
            actor.curves[id] = nil
        end
    end
end

-- Každá část trasy má vlastní křivku rychlosti (čas od začátku části): actor.curves.speed, speed<id>…
function Pe.curveId(id)
    return id == 1 and "speed" or ("speed" .. tostring(id))
end

-- Otisk všeho, na čem části trasy závisí (body, akce, zpoždění, rychlost, křivky): editor se ptá na části stokrát za snímek.
local function fingerprint(actor)
    local sum = (actor.delay or 0) * 0.37 + (actor.speed or 0) * 0.41
    for j, p in ipairs(actor.points or {}) do
        sum = sum + j * (p[1] * 1.3 + p[2] * 1.7 + (p[3] or 0) * 0.11 + (p[4] or 0) * 0.13 + (p[5] and 0.5 or 0) + (p[8] and 0.23 or 0)
            + (p[6] or 0) * 0.7 + (type(p[7]) == "number" and p[7] or (p[7] and 0.9 or 0)) * 0.19 + (p[9] or 0) * 0.29)
    end
    for k, a in ipairs(actor.actions or {}) do
        sum = sum + k * (a.t * 1.1 + (a.dur or 0) * 1.3 + (a.value or 0) * 0.5 + (a.leg or 0) * 0.3 + (a.kind == "seat" and 0.7 or 0))
            + (a.vehicle ~= nil and #a.vehicle * 0.01 or 0)
    end
    return sum, #(actor.points or {}), #(actor.actions or {})
end

local legsMemo = setmetatable({}, { __mode = "k" })

local buildLegs

function Pe.legs(actor)
    local sum, np, na = fingerprint(actor)
    local memo = legsMemo[actor]
    if memo ~= nil and memo.sum == sum and memo.np == np and memo.na == na then
        local fresh = true
        for _, leg in ipairs(memo.legs) do
        end
        if fresh then
            return memo.legs
        end
    end
    local legs = buildLegs(actor)
    legsMemo[actor] = { sum = sum, np = np, na = na, legs = legs }
    return legs
end

buildLegs = function(actor)
    local points = actor.points or {}
    local legs = { { id = 1, from = 1, start = actor.delay or 0, actor = actor } }
    local byLeg = {}
    for _, e in ipairs(Pe.exits(actor)) do
        if e.leg ~= nil then
            byLeg[e.leg] = e
        end
    end
    local cache = legActors[actor] or {}
    legActors[actor] = cache
    for j = 2, #points do
        local id = points[j][7]
        if id then
            legs[#legs].to = j - 1
            cache[id] = cache[id] or {}
            local e = byLeg[id]
            legs[#legs + 1] = { id = id, from = j, start = e ~= nil and e.t or nil, vehicle = e ~= nil and e.vehicle or nil,
                actor = cache[id] }
        end
    end
    legs[#legs].to = #points
    for k = 2, #legs do
        local leg = legs[k]
        leg.actor.points = { unpack(points, leg.from, leg.to) }
        leg.actor.speed, leg.actor.delay, leg.actor.walk = actor.speed, leg.start or 0, true
        leg.actor.curves = {}
    end
    return legs
end

function Pe.legById(actor, id)
    for _, leg in ipairs(Pe.legs(actor)) do
        if leg.id == id then
            return leg
        end
    end
    return nil
end

local function legOf(actor, j)
    for _, leg in ipairs(Pe.legs(actor)) do
        if j >= leg.from and j <= leg.to then
            return leg
        end
    end
    return nil
end

-- Čas (s od začátku záběru), kdy postava projde bodem j; nil, když část trasy nemá výstup na ose.
function Pe.pointTime(actor, j)
    local leg = legOf(actor, j)
    if leg == nil or leg.start == nil then
        return nil
    end
    local plan = R.plan(leg.actor)
    local cs = plan ~= nil and plan.route.ctrlS[j - leg.from + 1] or nil
    if cs == nil then
        return j == leg.from and leg.start or nil
    end
    return leg.start + R.timeAtS(plan, cs)
end

-- Konec chůze (s od začátku záběru): konec poslední části trasy, která se jde.
function Pe.walkEnd(actor)
    local finish = actor.delay or 0
    for _, leg in ipairs(Pe.legs(actor)) do
        local plan = R.plan(leg.actor)
        if leg.start ~= nil then
            finish = math.max(finish, leg.start + (plan ~= nil and plan.total or 0))
        end
    end
    return finish
end

-- Kam se postava v bodě k dívá: zadané natočení p[6], jinak směr chůze do bodu (na startu natočení ze startu, na začátku
-- další části směr, kterým odchází). Druhá hodnota říká, jestli je natočení zadané.
function Pe.pointFacing(actor, k)
    local p = actor.points[k]
    if p ~= nil and p[6] ~= nil then
        return p[6], true
    end
    return Pe.walkHeading(actor, k), false
end

-- Směr chůze v bodě k (bez zadaného natočení).
function Pe.walkHeading(actor, k)
    local leg = legOf(actor, k) or { from = 1, actor = actor }
    local plan = R.plan(leg.actor)
    local i = k - leg.from + 1
    if plan == nil or i == 1 or plan.route.ctrlS[i] == nil then
        local ps = actor.start ~= nil and actor.start.person or nil
        if ps ~= nil and leg.from == 1 then
            return ps.yaw
        end
        return plan ~= nil and R.headingAt(plan.route, 0) or 0
    end
    return R.headingAt(plan.route, math.max(plan.route.ctrlS[i] - 0.01, 0))
end

Pe.FLOOR_MIN = 0.3 -- m nad terénem; bod trasy výš (podlaha, schody, patro) si výšku pamatuje v p[9], níž jde po terénu

Pe.FLOOR_ABOVE = 1.2 -- m nad plánovanou výškou začíná paprsek, který hledá skutečný schod nebo podlahu pod postavou
Pe.FLOOR_BELOW = 0.8 -- m pod plánovanou výškou ho ještě vezme

-- Výška nohou postavy v x, z: plán mezi body trasy dělá rampu, schody jsou ale stupně a podesty — paprsek shora najde
-- skutečný povrch poblíž plánu (nad hlavou ani hluboko pod plánem nic nebere); bez zásahu platí plán.
function Pe.snapFloor(x, y, z)
    local hit = CinemaWorld.raycastAny(x, y + Pe.FLOOR_ABOVE, z, 0, -1, 0, Pe.FLOOR_ABOVE + Pe.FLOOR_BELOW)
    return hit or y
end

-- Výška, na které bod trasy stojí: podlaha z p[9], jinak terén.
function Pe.pointY(p)
    return p[9] or CinemaWorld.terrainY(p[1], p[2])
end

-- Výška chůze v místě s po trase (x, z) mezi body points: výška nad terénem se mezi body mění plynule (schody, žebřík),
-- bez bodů s podlahou je to terén.
function Pe.floorY(points, route, s, x, z)
    local ground = CinemaWorld.terrainY(x, z)
    local any = false
    for _, p in ipairs(points) do
        any = any or p[9] ~= nil
    end
    if not any or route == nil then
        return ground
    end
    local function above(j)
        local p = points[j]
        return p ~= nil and p[9] ~= nil and p[9] - CinemaWorld.terrainY(p[1], p[2]) or 0
    end
    local cs = route.ctrlS
    if s <= (cs[1] or 0) then
        return ground + above(1)
    end
    for j = 1, #cs - 1 do
        if s <= cs[j + 1] then
            local len = cs[j + 1] - cs[j]
            local u = len > 1e-6 and (s - cs[j]) / len or 1
            return ground + above(j) + (above(j + 1) - above(j)) * u
        end
    end
    return ground + above(#cs)
end

-- Bod trasy j, ve kterém postava v místě s po trase stojí (pauza nebo konec), nebo nil.
local function pointAt(plan, s)
    for j, cs in ipairs(plan.route.ctrlS) do
        if math.abs(cs - s) < 1e-3 then
            return j
        end
    end
    return nil
end

Pe.EXIT_BLEND = 3 -- s; za jak dlouho po výstupu postava přejde od skutečného vozidla na naplánovanou trasu

local legPoseOnRoute

-- Část trasy od výstupu začíná u vozidla, jak stojí podle plánu; skutečné vozidlo (fyzika, náhled mimo přehrávání) může
-- stát jinde, a pak postava vystoupí u něj a během Pe.EXIT_BLEND plynule přejde na trasu.
local function legPose(actor, leg, t)
    local x, z, yaw, y = legPoseOnRoute(actor, leg, t)
    local v = leg.vehicle ~= nil and leg.start ~= nil and CinemaWorld.find(leg.vehicle) or nil
    local p1 = actor.points[leg.from]
    if v ~= nil and p1 ~= nil then
        local fade = M.clamp(1 - (t - leg.start) / Pe.EXIT_BLEND, 0, 1)
        if fade > 0 then
            local vx, vz = Pe.exitPose(v)
            x, z = x + (vx - p1[1]) * fade, z + (vz - p1[2]) * fade
            y = CinemaWorld.terrainY(x, z)
        end
    end
    return x, z, yaw, y
end

legPoseOnRoute = function(actor, leg, t)
    local plan = R.plan(leg.actor)
    local p1 = actor.points ~= nil and actor.points[leg.from] or nil
    if plan == nil or t <= leg.start then
        local ps = leg.from == 1 and actor.start ~= nil and actor.start.person or nil
        local yaw = p1 ~= nil and p1[6] or (ps ~= nil and ps.yaw) or (plan ~= nil and R.headingAt(plan.route, 0)) or 0
        if p1 ~= nil then
            return p1[1], p1[2], yaw, Pe.pointY(p1)
        end
        local x, z = ps ~= nil and ps.x or 0, ps ~= nil and ps.z or 0
        return x, z, yaw, CinemaWorld.terrainY(x, z)
    end
    local x, z, s, heading = R.positionAtTime(plan, t - leg.start)
    local y = Pe.floorY(leg.actor.points, plan.route, s, x, z)
    local j = pointAt(plan, s)
    local p = j ~= nil and actor.points[leg.from + j - 1] or nil
    if p ~= nil and p[6] ~= nil then
        return x, z, p[6], y
    end
    return x, z, heading, y
end

-- Část trasy, kterou postava v čase t jde (nil, když sedí ve vozidle nebo po výstupu další část není), a stav nástupu.
local function legAt(actor, legs, t)
    local seat = Pe.seatAt(actor, t)
    if seat == nil then
        return legs[1], nil
    elseif seat.inside then
        return nil, seat
    end
    local last = nil
    for _, e in ipairs(Pe.exits(actor)) do
        if e.t <= t + 1e-6 then
            last = e
        end
    end
    for _, leg in ipairs(legs) do
        if last ~= nil and leg.id == last.leg and leg.start ~= nil then
            return leg, seat
        end
    end
    return nil, seat
end

-- Kde má postava v čase t (s od začátku záběru) stát a kam se dívat: x, z, yaw, y (výška nohou: terén, nebo podlaha
-- z bodů trasy). Natočení bodu platí, když v něm stojí.
-- Po výstupu z vozidla jde další částí trasy; když žádná není, stojí u dveří vozidla.
function Pe.poseAt(actor, t)
    local legs = Pe.legs(actor)
    local leg, seat = legAt(actor, legs, t)
    if leg ~= nil then
        return legPose(actor, leg, t)
    end
    local v = seat ~= nil and not seat.inside and CinemaWorld.find(seat.vehicle) or nil
    if v ~= nil then
        local x, z, yaw = Pe.exitPose(v)
        return x, z, yaw, CinemaWorld.terrainY(x, z)
    end
    return legPose(actor, legs[1], t)
end

-- Rychlost chůze (km/h) v čase t podle části trasy, kterou postava jde; ve vozidle a po výstupu bez další části 0.
-- Přeskok z místa nástupu k výstupu se nepočítá.
function Pe.speedAt(actor, t)
    local leg = legAt(actor, Pe.legs(actor), t)
    local plan = leg ~= nil and R.plan(leg.actor) or nil
    local local_t = t - (leg ~= nil and leg.start or 0)
    if plan == nil or local_t < 0 then
        return 0
    end
    -- po dráze, ne vzdušnou čarou: v ostré zatáčce by tětiva ukázala pomalejší chůzi, než je
    local a, b = math.max(local_t - 0.2, 0), local_t + 0.2
    local _, _, s1 = R.positionAtTime(plan, a)
    local _, _, s2 = R.positionAtTime(plan, b)
    return math.abs(s2 - s1) / (b - a) * 3.6
end

-- Dveře vozidla (exitPoint) v souřadnicích vozidla: lx, lz.
function Pe.exitOffset(v)
    local node = v.getExitNode ~= nil and v:getExitNode(player()) or nil
    if node == nil or node == 0 then
        return 0, 0
    end
    local lx, _, lz = worldToLocal(v.rootNode, getWorldTranslation(node))
    return lx, lz
end

-- Kde postava po výstupu z vozidla stojí: u dveří (exitPoint vozidla), čelem jako vozidlo. x, z, yaw.
function Pe.exitPose(v)
    local lx, lz = Pe.exitOffset(v)
    local x, _, z = localToWorld(v.rootNode, lx, 0, lz)
    local dx, _, dz = localDirectionToWorld(v.rootNode, 0, 0, 1)
    return x, z, math.atan2(dx, dz)
end

-- Kde postava vystoupí při výstupu exit: vozidlo herce v ten čas podle plánu jeho trasy, jiné vozidlo tam, kde stojí.
local function exitPosition(actors, exit)
    local v = exit ~= nil and CinemaWorld.find(exit.vehicle) or nil
    if v == nil then
        return nil
    end
    for _, a in ipairs(actors) do
        local first = a.start ~= nil and a.start.entries ~= nil and a.start.entries[1] or nil
        local plan = first ~= nil and first.uid == exit.vehicle and R.plan(a) or nil
        if plan ~= nil then
            local _, _, s = R.positionAtTime(plan, math.max(exit.t - (a.delay or 0), 0))
            -- řízení zastaví vozidlo už R.ARRIVE před pauzou nebo koncem trasy (W.driveActor), ne v bodě samém
            local stopS = R.nextStopS(plan.route, s - R.ARRIVE - 0.01) or plan.route.length
            s = math.max(math.min(s, stopS - R.ARRIVE), 0)
            local x, z = R.pointAt(plan.route, s)
            local h = R.bodyHeadingAt(plan.route, s)
            local lx, lz = Pe.exitOffset(v)
            return x + lx * math.cos(h) + lz * math.sin(h), z - lx * math.sin(h) + lz * math.cos(h)
        end
    end
    local x, z = Pe.exitPose(v)
    return x, z
end

-- Body výstupu (p[7] = id části) podle výstupů na ose: každý výstup má svůj bod (nový se přidá na konec trasy, odkud se
-- kreslí dál), který stojí tam, kde postava z vozidla vystoupí; s p[8] (ruční poloha, povolí se v menu bodu) ho uživatel
-- posouvá sám a od dveří k němu postava dojde během Pe.EXIT_BLEND. Bod výstupu, který na ose chybí, i s body své části
-- zůstane (nejde se), aby se část nenapojila jinam. Vrací true, když něco změnila.
function Pe.syncExitPoints(actors)
    local changed = false
    for _, actor in ipairs(actors) do
        if Pe.isPerson(actor) and actor.points ~= nil and #actor.points > 0 then
            changed = Pe.assignLegIds(actor) or changed
            local byLeg = {}
            for j = 2, #actor.points do
                local p = actor.points[j]
                if p[7] then
                    byLeg[p[7]] = p
                end
            end
            for _, e in ipairs(Pe.exits(actor)) do
                local x, z = exitPosition(actors, e)
                local p = byLeg[e.leg]
                if x ~= nil and p == nil then
                    actor.points[#actor.points + 1] = { x, z, [7] = e.leg }
                    changed = true
                elseif x ~= nil and not p[8] and (math.abs(p[1] - x) > 0.05 or math.abs(p[2] - z) > 0.05) then
                    p[1], p[2] = x, z
                    changed = true
                end
            end
        end
    end
    return changed
end

-- Je bod j bodem výstupu, jehož výstup na ose už není? (nil, když to bod výstupu není)
function Pe.isOrphanExit(actor, j)
    local p = actor.points[j]
    if p == nil or not p[7] then
        return nil
    end
    local leg = Pe.legById(actor, p[7])
    return leg ~= nil and leg.start == nil
end

-- Smaže část trasy, která začíná bodem výstupu j (body až k další části a křivku rychlosti), když už na ose nemá výstup.
function Pe.removeOrphanLeg(actor, j)
    if not Pe.isOrphanExit(actor, j) then
        return false
    end
    local id = actor.points[j][7]
    local leg = Pe.legById(actor, id)
    for k = leg.to, leg.from, -1 do
        table.remove(actor.points, k)
    end
    if actor.curves ~= nil then
        actor.curves[Pe.curveId(id)] = nil
    end
    return true
end

function Pe.playerVehicle()
    local p = player()
    if p == nil or p.getCurrentVehicle == nil then
        return nil
    end
    return p:getCurrentVehicle()
end

-- Hráč nasedne do vozidla (i z dálky, ověřeno sondou). Hra přitom přepne na kameru vozidla; naši vrací Pe.keepCamera.
function Pe.enter(v)
    local p = player()
    if p == nil or v == nil or Pe.playerVehicle() == v then
        return
    end
    if Pe.playerVehicle() ~= nil then
        pcall(function() p:leaveVehicle() end)
    end
    Pe.feed = nil
    pcall(function() p:requestToEnterVehicle(v) end)
    Pe.entered = true
end

function Pe.leave()
    local p = player()
    if p ~= nil and Pe.playerVehicle() ~= nil then
        pcall(function() p:leaveVehicle() end)
    end
end

-- Nástup i výstup hráče přepnou kameru; v editoru s postavou musí zůstat aktivní ta naše.
function Pe.keepCamera(cam)
    if cam ~= nil and cam.active and cam.node ~= nil and g_cameraManager:getActiveCamera() ~= cam.node then
        g_cameraManager:setActiveCamera(cam.node)
    end
end

local function turnTowards(yaw, target, dt)
    local diff = M.angleDiff(yaw, target)
    local step = Pe.TURN_RATE * dt * 0.001
    if math.abs(diff) <= step then
        return target, true
    end
    return yaw + (diff > 0 and step or -step), false
end

-- Hráč na místo, kde má postava být v čase t, natočený podle plánu. Z vozidla nejdřív vystoupí; cam = kamera editoru,
-- kterou výstup z vozidla přepne na hráčovu.
function Pe.place(actor, t, cam)
    if Pe.isHelper(actor) then
        return true
    end
    local p = player()
    if p == nil then
        return false, "missing"
    end
    if p.getCurrentVehicle ~= nil and p:getCurrentVehicle() ~= nil then
        pcall(function() p:leaveVehicle() end)
    end
    -- do vozidla ho případně posadí akce
    local x, z, yaw, y = Pe.poseAt(actor, t)
    y = Pe.snapFloor(x, y, z)
    local ok = pcall(function() p:teleportTo(x, y + 0.05, z) end)
    if p.setMovementYaw ~= nil then
        pcall(p.setMovementYaw, p, yaw)
    end
    if cam ~= nil and cam.active and cam.node ~= nil then
        g_cameraManager:setActiveCamera(cam.node)
    end
    Pe.feed = nil
    return ok, ok and nil or "missing"
end

function Pe.newRuntime(actor)
    return { person = true, state = "waiting", name = actor.name }
end

-- Jeden snímek přehrávání: vstup, který dovede hráče na plánovanou polohu; stojí-li, otočí ho podle plánu. Ve vozidle
-- nedělá nic, po výstupu jde další částí trasy.
function Pe.update(rt, actor, t, dt)
    if Pe.isHelper(actor) then
        return
    end
    local p = player()
    local seat = Pe.seatAt(actor, t)
    if p == nil or Pe.playerVehicle() ~= nil or (seat ~= nil and seat.inside) then
        Pe.feed = nil
        return
    end
    local x, _, z = Pe.playerPos()
    local tx, tz, yaw = Pe.poseAt(actor, t)
    local nx, nz = Pe.poseAt(actor, t + 0.1)
    local vx = (nx - tx) / 0.1 + (tx - x) * Pe.CATCH_UP
    local vz = (nz - tz) / 0.1 + (tz - z) * Pe.CATCH_UP
    local speed = math.sqrt(vx * vx + vz * vz)
    if speed < Pe.IDLE_MPS then
        Pe.feed = nil
        local current = Pe.playerYaw()
        if math.abs(M.angleDiff(current, yaw)) > 0.01 and p.setMovementYaw ~= nil then
            pcall(p.setMovementYaw, p, (turnTowards(current, yaw, dt)))
        end
        return
    end
    local run = 0
    if speed > Pe.GAME_WALK_MPS * 1.05 then
        run = M.clamp((speed - Pe.GAME_WALK_MPS) / (Pe.RUN_MPS - Pe.GAME_WALK_MPS), 0.1, 1)
    end
    Pe.feed = { dirX = vx / speed, dirZ = vz / speed, axis = M.clamp(speed / Pe.GAME_WALK_MPS, 0.1, 1), run = run }
end

function Pe.stop()
    Pe.feed = nil
end

-- Kamera editoru skryje model hráče; postava v záběru ale vidět být musí. Po zavření editoru v první osobě model zase schovat.
function Pe.keepVisible()
    local p = player()
    if p ~= nil and p.graphicsComponent ~= nil and (p.getCurrentVehicle == nil or p:getCurrentVehicle() == nil) then
        p.graphicsComponent:setModelVisibility(true)
        Pe.forcedVisible = true
    end
end

---------------------------------------------------------------------------------------------------
-- pomocník: vlastní HumanGraphicsComponent se stylem pomocníka (ověřeno sondou: chodí s animací, výška = terén)

Pe.npcs = {} -- actor → { gc, state, loaded, helper, x, z, yaw }

local function newNpc(name, style)
    local npc = { helper = name }
    local ok = pcall(function()
        local gc = HumanGraphicsComponent.new()
        gc:initialize()
        npc.gc = gc
        gc:setStyleAsync(style, function() npc.loaded = true end, nil, nil, false, nil, false)
        npc.state = HumanGraphicsComponentState.new()
    end)
    return ok and npc or nil
end

-- Pomocník sedí ve vozidle v (nil = nikde): za volantem je jeho postava, po výstupu je vozidlo prázdné (vozidlo, do
-- kterého postava nastupuje, jiného řidiče nemá, viz syncDrivers editoru).
local function seatNpc(npc, actor, v)
    local uid = v ~= nil and CinemaWorld.uid(v) or nil
    if npc.seatedIn == uid then
        return
    end
    local old = npc.seatedIn ~= nil and CinemaWorld.find(npc.seatedIn) or nil
    if old ~= nil then
        CinemaWorld.setDriver(old, nil)
    end
    if v ~= nil then
        CinemaWorld.setDriver(v, actor.helper, actor.look ~= nil and Pe.actorStyle(actor) or nil)
    end
    npc.seatedIn = uid
end

local function setNpcVisible(npc, visible)
    if (npc.hidden == true) == not visible then
        return
    end
    npc.hidden = not visible or nil
    pcall(function() npc.gc:setModelVisibility(visible) end)
end

local function deleteNpc(npc)
    seatNpc(npc, nil, nil)
    if npc.gc ~= nil then
        pcall(function() npc.gc:delete() end)
    end
end

local function poseNpc(npc, x, y, z, yaw, speed, turn, dt)
    local gc, st = npc.gc, npc.state
    local running = speed > (Pe.WALK_MPS + Pe.RUN_MPS) * 0.5
    st.absSpeed, st.isWalking, st.isRunning, st.isIdling = speed, speed > 0.05 and not running, running, speed <= 0.05
    st.isGrounded, st.isCloseToGround, st.distanceToGround, st.isNPC = true, true, 0, true
    st.relativeVelocityX, st.relativeVelocityY, st.relativeVelocityZ = 0, 0, speed
    st.movementDirX, st.movementDirZ, st.rotationVelocity = 0, 1, turn
    st.movementSpeed, st.isOnGround, st.yawVelocity = speed, true, turn
    pcall(function()
        gc:applyState(st)
        gc:setModelYaw(yaw)
        gc:setModelPosition(x, y, z)
        gc:update(dt)
    end)
end

-- Každý snímek editoru: pomocníci z actors stojí, kde je chce trasa v čase t; moving = čas běží (jinak bez animace chůze).
-- Pomocníci herců, kteří už v záběru nejsou, zmizí.
function Pe.syncHelpers(actors, t, dt, moving)
    local seen = {}
    for _, actor in ipairs(actors) do
        if Pe.isHelper(actor) then
            seen[actor] = true
            local npc = Pe.npcs[actor]
            local key = Pe.lookKey(actor)
            if npc ~= nil and npc.key ~= key then
                deleteNpc(npc)
                npc = nil
            end
            if npc == nil then
                local style = Pe.actorStyle(actor)
                npc = style ~= nil and newNpc(actor.helper, style) or { helper = actor.helper }
                npc.key = key
                Pe.npcs[actor] = npc
            end
            if npc.loaded then
                local seat = Pe.seatAt(actor, t)
                local v = seat ~= nil and CinemaWorld.find(seat.vehicle) or nil
                seatNpc(npc, actor, seat ~= nil and seat.inside and v or nil)
                if npc.seatedIn ~= nil then
                    setNpcVisible(npc, false)
                    npc.x = nil
                else
                    setNpcVisible(npc, true)
                    local x, z, yaw, y = Pe.poseAt(actor, t)
                    y = Pe.snapFloor(x, y, z)
                    local speed, turn = 0, 0
                    if moving and npc.x ~= nil and dt > 0 then
                        -- rychlost z plánu, ne z posunu za snímek: skok ukazatele nebo start přehrávání by dal na pár
                        -- snímků obří rychlost a model by se rozběhl
                        speed = Pe.speedAt(actor, t) / 3.6
                        yaw = (turnTowards(npc.yaw, yaw, dt))
                        turn = M.angleDiff(npc.yaw, yaw) / (dt * 0.001)
                    end
                    npc.x, npc.y, npc.z, npc.yaw = x, y, z, yaw
                    poseNpc(npc, x, y, z, yaw, speed, turn, dt)
                end
            end
        end
    end
    for actor, npc in pairs(Pe.npcs) do
        if not seen[actor] then
            deleteNpc(npc)
            Pe.npcs[actor] = nil
        end
    end
end

---------------------------------------------------------------------------------------------------
-- nesení předmětu ze světa: postava zvedne předmět, který ve světě leží (vybraný ve scéně: malé vozidlo hry — paleta,
-- kanystr, IBC — nebo předmět mapy s kolizí), odnese ho a na konci akce položí, kde zrovna je. action.carry = { kind =
-- "vehicle", uid } nebo { kind = "node", name } a x, y, z, rx, ry, rz = kde předmět leží, r = poloměr. Před akcí se předmět
-- vrátí na své místo, takže posun ukazatele zpět ho vrátí. Postava nemá animaci nesení, ruce se houpou dál.

Pe.CARRY_LIFT = 0.6 -- s; zvednutí na začátku a položení na konci akce
Pe.CARRY_ONE_HAND = 0.3 -- m; předmět s poloměrem do tolika nese v jedné ruce u boku, větší oběma před sebou
Pe.CARRY_MAX = 1.5 -- m; větší objekt (stroj, budova) postava nezvedne
Pe.CARRY_GROUP = 6 -- uzel s víc dětmi je skupina předmětů mapy, ne předmět
-- křivky posunu předmětu proti místu v rukou (m): doleva, výš, dopředu
Pe.CARRY_CURVES = { "carryX", "carryY", "carryZ" }
-- křivky natočení (°): naklonit dopředu (vysypat), naklonit do strany, otočit kolem svislé osy
Pe.CARRY_TURNS = { "carryRx", "carryRz", "carryRy" }
-- akce nesení → { target, state, moved, lifted }
Pe.carried = {}
-- cíl nesení → uzel předmětu mapy (po načtení záběru se najde znovu podle místa a jména)
Pe.carryNodes = setmetatable({}, { __mode = "k" })

-- Předmět mapy, do kterého patří zasažený tvar: stoupá k rodiči, dokud rodič není skupina předmětů nebo kořen scény.
function Pe.objectRoot(shape)
    local node = shape
    while true do
        local parent = getParent(node)
        if parent == nil or parent == 0 or parent == getRootNode() or parent == g_terrainNode or getNumOfChildren(parent) > Pe.CARRY_GROUP then
            return node
        end
        node = parent
    end
end

local function poseOf(node)
    local x, y, z = getWorldTranslation(node)
    local rx, ry, rz = getWorldRotation(node)
    return x, y, z, rx, ry, rz
end

-- Cíl nesení z vozidla (paleta, kanystr…), nil u velkého stroje.
function Pe.carryFromVehicle(v)
    local size = v.size or {}
    local r = math.max(size.width or 0, size.length or 0, size.height or 0) * 0.5
    if r > Pe.CARRY_MAX then
        return nil
    end
    local x, y, z, rx, ry, rz = poseOf(v.rootNode)
    return { kind = "vehicle", uid = CinemaWorld.uid(v), name = CinemaWorld.name(v), r = r, x = x, y = y, z = z, rx = rx, ry = ry, rz = rz }
end

-- Cíl nesení z tvaru zasaženého paprskem (předmět mapy), nil u velkého objektu.
function Pe.carryFromShape(shape)
    local r = Pe.CARRY_ONE_HAND
    if getShapeBoundingSphere ~= nil then
        local ok, _, _, _, radius = pcall(getShapeBoundingSphere, shape)
        r = ok and radius or r
    end
    if r > Pe.CARRY_MAX then
        return nil
    end
    local node = Pe.objectRoot(shape)
    local x, y, z, rx, ry, rz = poseOf(node)
    local target = { kind = "node", name = getName(node), r = r, x = x, y = y, z = z, rx = rx, ry = ry, rz = rz }
    Pe.carryNodes[target] = node
    return target
end

-- Vozidlo nebo uzel, se kterým akce hýbe; nil, když ve světě není. Předmět mapy se po načtení najde paprskem shora na
-- místě, kde leží, a podle jména.
local function carryHandle(target)
    if target.kind == "vehicle" then
        local v = CinemaWorld.find(target.uid)
        return v, nil
    end
    local node = Pe.carryNodes[target]
    if node ~= nil and entityExists(node) then
        return nil, node
    end
    local shape = CinemaWorld.raycastShape(target.x, target.y + 1, target.z, 0, -1, 0, 2)
    node = shape ~= nil and Pe.objectRoot(shape) or nil
    if node ~= nil and getName(node) == target.name then
        Pe.carryNodes[target] = node
        return nil, node
    end
    return nil, nil
end

local function curveValues(actor, t, ids)
    local tl = t - (actor.delay or 0)
    local out = {}
    for k, id in ipairs(ids) do
        local ch = actor.curves ~= nil and actor.curves[id] or nil
        out[k] = CinemaChannels.hasPoints(ch) and CinemaChannels.valueAt(ch, tl) or 0
    end
    return out[1], out[2], out[3]
end

-- Posun předmětu z křivek v čase t: doleva, výš, dopředu.
function Pe.carryOffset(actor, t)
    return curveValues(actor, t, Pe.CARRY_CURVES)
end

-- Natočení předmětu z křivek v čase t v radiánech: náklon dopředu, do strany, otočení.
function Pe.carryTurn(actor, t)
    local rx, rz, ry = curveValues(actor, t, Pe.CARRY_TURNS)
    return math.rad(rx), math.rad(rz), math.rad(ry)
end

-- Kde předmět drží vůči postavě (x doleva, y výška počátku předmětu nad zemí, z dopředu): malý v jedné ruce u boku, větší
-- oběma před sebou.
function Pe.holdOffset(target)
    if (target.r or 0) <= Pe.CARRY_ONE_HAND then
        return -0.25, 0.35, 0.05
    end
    return 0, 0.85, 0.3 + target.r * 0.5
end

-- Kde postava stojí: x, y (zem), z, natočení; nil, když není vidět (sedí ve vozidle).
local function bodyPose(actor)
    if Pe.isHelper(actor) then
        local npc = Pe.npcs[actor]
        if npc == nil or npc.x == nil or npc.hidden then
            return nil
        end
        return npc.x, npc.y or CinemaWorld.terrainY(npc.x, npc.z), npc.z, npc.yaw or 0
    end
    if Pe.playerVehicle() ~= nil then
        return nil
    end
    local x, y, z = Pe.playerPos()
    return x, y, z, Pe.playerYaw()
end

-- Místo ve světě pro postavu v x, y, z s natočením yaw a místem vůči ní ox (doleva), oy, oz (dopředu).
function Pe.carryWorld(x, y, z, yaw, ox, oy, oz)
    local s, c = math.sin(yaw), math.cos(yaw)
    return x + ox * c + oz * s, y + oy, z - ox * s + oz * c
end

-- O kolik je předmět v rukou natočený proti postavě: jak ležel vůči tomu, jak postava při zvednutí stála.
local function heldYaw(actor, action)
    local _, _, yaw = Pe.poseAt(actor, action.t + (actor.delay or 0))
    return action.carry.ry - yaw
end

-- Kde předmět po položení leží: na podlaze pod místem, kde ho postava podle plánu na konci akce nese, otočený jako v rukou.
function Pe.carryDrop(actor, action)
    local target = action.carry
    local t = action.t + action.dur + (actor.delay or 0)
    local x, z, yaw, y = Pe.poseAt(actor, t)
    local dx, _, dz = Pe.carryOffset(actor, t)
    local _, _, ry = Pe.carryTurn(actor, t)
    local ox, _, oz = Pe.holdOffset(target)
    local px, py, pz = Pe.carryWorld(x, y, z, yaw, ox + dx, 0, oz + dz)
    return px, py, pz, target.rx, yaw + heldYaw(actor, action) + ry, target.rz
end

-- Poloha předmětu akce v čase t: x, y, z, rx, ry, rz a stav "rest" (leží na svém místě), "held" (v rukou), "dropped"
-- (položený); nil, když ho postava nese a není vidět (sedí ve vozidle).
function Pe.carryPose(actor, action, t)
    local target = action.carry
    local tl = t - (actor.delay or 0)
    if tl < action.t then
        return target.x, target.y, target.z, target.rx, target.ry, target.rz, "rest"
    end
    if action.dur ~= nil and tl >= action.t + action.dur then
        local x, y, z, rx, ry, rz = Pe.carryDrop(actor, action)
        return x, y, z, rx, ry, rz, "dropped"
    end
    local bx, by, bz, byaw = bodyPose(actor)
    if bx == nil then
        return nil
    end
    local ox, oy, oz = Pe.holdOffset(target)
    local dx, dy, dz = Pe.carryOffset(actor, t)
    local trx, trz, try = Pe.carryTurn(actor, t)
    local x, y, z = Pe.carryWorld(bx, by, bz, byaw, ox + dx, oy + dy, oz + dz)
    local rx, ry, rz = target.rx + trx, byaw + heldYaw(actor, action) + try, target.rz + trz
    -- zvednutí a položení: plynule mezi místem na zemi a rukama, náklon z křivek naběhne s ním
    local lift = action.dur ~= nil and math.min(Pe.CARRY_LIFT, action.dur * 0.5) or Pe.CARRY_LIFT
    local from, u = nil, 1
    if tl < action.t + lift then
        from, u = { target.x, target.y, target.z, target.rx, target.ry, target.rz }, (tl - action.t) / lift
    elseif action.dur ~= nil and tl > action.t + action.dur - lift then
        from, u = { Pe.carryDrop(actor, action) }, (action.t + action.dur - tl) / lift
    end
    if from ~= nil then
        u = M.smoothstep(M.clamp(u, 0, 1))
        x, y, z = from[1] + (x - from[1]) * u, from[2] + (y - from[2]) * u, from[3] + (z - from[3]) * u
        rx, rz = from[4] + (rx - from[4]) * u, from[6] + (rz - from[6]) * u
        ry = from[5] + M.angleDiff(from[5], ry) * u
    end
    return x, y, z, rx, ry, rz, "held"
end

-- Postaví předmět: v rukou bez fyziky (vozidlo), položený nebo na svém místě zase s fyzikou. Předmětu, se kterým se ještě
-- nehýbalo, se na jeho místě nesahá.
local function placeCarry(c, x, y, z, rx, ry, rz, state)
    if state == "rest" and not c.moved then
        c.state = state
        return
    end
    local v, node = carryHandle(c.target)
    if v ~= nil then
        if state == "held" or c.state ~= state then
            if not c.lifted then
                v:removeFromPhysics()
                c.lifted = true
            end
            v:setAbsolutePosition(x, y, z, rx, ry, rz)
            if state ~= "held" then
                v:addToPhysics()
                c.lifted = false
            end
        end
    elseif node ~= nil then
        setWorldTranslation(node, x, y, z)
        setWorldRotation(node, rx, ry, rz)
    end
    c.state, c.moved = state, c.moved or state ~= "rest"
end

-- Předmět zpátky na místo, kde ležel (akce zmizela, editor se zavírá).
local function restoreCarry(action)
    local c = Pe.carried[action]
    Pe.carried[action] = nil
    if c ~= nil and c.moved then
        local t = c.target
        placeCarry(c, t.x, t.y, t.z, t.rx, t.ry, t.rz, "back")
    end
end

-- Každý snímek editoru: předmět každé akce nesení leží na svém místě, je v rukou, nebo leží položený podle času.
function Pe.syncCarry(actors, t)
    local seen = {}
    for _, actor in ipairs(actors) do
        for _, action in ipairs(Pe.isPerson(actor) and actor.actions or {}) do
            if action.kind == "carry" and (action.value or 1) == 1 and action.carry ~= nil then
                local c = Pe.carried[action]
                if c ~= nil and c.target ~= action.carry then
                    restoreCarry(action)
                    c = nil
                end
                if c == nil then
                    c = { target = action.carry }
                    Pe.carried[action] = c
                end
                seen[action] = true
                local x, y, z, rx, ry, rz, state = Pe.carryPose(actor, action, t)
                if x ~= nil then
                    placeCarry(c, x, y, z, rx, ry, rz, state)
                end
            end
        end
    end
    for action in pairs(Pe.carried) do
        if not seen[action] then
            restoreCarry(action)
        end
    end
end

function Pe.release()
    for action in pairs(Pe.carried) do
        restoreCarry(action)
    end
    for actor, npc in pairs(Pe.npcs) do
        deleteNpc(npc)
        Pe.npcs[actor] = nil
    end
    Pe.feed = nil
    -- do vozidla posadila hráče osa; po zavření editoru stojí zase venku
    if Pe.entered then
        Pe.leave()
        Pe.entered = nil
    end
    local p = player()
    if Pe.forcedVisible and p ~= nil and p.graphicsComponent ~= nil and p.camera ~= nil and p.camera.isFirstPerson then
        p.graphicsComponent:setModelVisibility(false)
    end
    Pe.forcedVisible = nil
end

-- Vstup se dosazuje až po PlayerInputComponent.update: stavový automat ho čte hned potom a resetState ho na konci snímku smaže.
function Pe.feedInput(ic)
    local feed = Pe.feed
    if feed == nil or ic.player ~= g_localPlayer then
        return
    end
    ic.moveForward, ic.moveRight = 1, 0
    ic.worldDirectionX, ic.worldDirectionZ = feed.dirX, feed.dirZ
    ic.walkAxis, ic.runAxis = feed.axis, feed.run or 0
    ic.hasMovementInputs = true
end

if PlayerInputComponent ~= nil and PlayerInputComponent.update ~= nil and not PlayerInputComponent.cinemaStudioHooked then
    PlayerInputComponent.cinemaStudioHooked = true
    PlayerInputComponent.update = Utils.appendedFunction(PlayerInputComponent.update, function(ic) CinemaPerson.feedInput(ic) end)
end
