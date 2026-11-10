-- Bloky jízdy herce na ose: úsek trasy (od bodu j po odjezdu do bodu j + 1), pauza v bodě (p[4]) a stání z křivky
-- rychlosti. Každý jde vybrat sám, táhnout (úsek = začne později / dřív, kraj úseku = délka, tj. rychlost; pauza a stání =
-- délka), smazat, rozdělit a má své menu. Celá jízda se vybírá obdélníkem nebo z menu úseku. Akce a křivky herce za
-- změnou se posouvají s ní (ripple), ať zůstanou na stejném místě trasy.

local E = CinemaEditorScreen
local S = CinemaShot
local R = CinemaRoute
local Ch = CinemaChannels
local Pe = CinemaPerson
local A = CinemaActions
local M = CinemaMath

E.SPAN_EDGE_PX = 7 -- jak blízko konce úseku (px) se chytá jeho délka
E.SPAN_MIN = 0.2 -- s; nejkratší úsek při natahování
E.SPAN_STEP = 0.5 -- s; krok délky a začátku v menu
E.SPAN_MIN_WAIT = 0.1 -- s; nejkratší pauza, kterou posun úseku vytvoří

local function t(key)
    return g_i18n:getText(key)
end

local function speedCurve(actor)
    local curve = actor ~= nil and actor.curves ~= nil and actor.curves.speed or nil
    return Ch.hasPoints(curve) and curve or nil
end

-- Bloky jízdy herce i v čase záběru: { kind = "span" | "wait" | "stop", j | k, t0, t1 }. Úsek do bodu výstupu z vozidla
-- není (postava mezitím sedí ve vozidle).
function E:actorSpanList(i)
    local a = self.shot.actors[i]
    local list = {}
    if a == nil then
        return list
    end
    local curve = speedCurve(a)
    for j = 1, #(a.points or {}) - 1 do
        local from, to = self:routePointTime(i, j), self:routePointTime(i, j + 1)
        if from ~= nil and to ~= nil and not a.points[j + 1][7] then
            local wait = not curve and a.points[j][4] or 0
            if wait > 0 then
                list[#list + 1] = { kind = "wait", j = j, t0 = from, t1 = from + wait }
            end
            if to > from + wait + 1e-3 then
                list[#list + 1] = { kind = "span", j = j, t0 = from + wait, t1 = to }
            end
        end
    end
    for k = 2, #(curve ~= nil and curve.points or {}) do
        if Ch.isStopEnd(curve, k) then
            list[#list + 1] = { kind = "stop", k = k, t0 = (a.delay or 0) + curve.points[k - 1].t, t1 = (a.delay or 0) + curve.points[k].t }
        end
    end
    return list
end

-- Blok pod kurzorem v řádku herce i: stání a pauzy mají přednost (leží přes úsek), part = "end" u konce bloku.
function E:spanAtScreen(i, x)
    local tm = self:timeAtX(x)
    local edge = E.SPAN_EDGE_PX * g_pixelSizeScaledX
    local best = nil
    for _, e in ipairs(self:actorSpanList(i)) do
        if tm >= e.t0 and tm <= e.t1 + self:timeAtX(x + edge) - tm then
            if best == nil or (best.kind == "span" and e.kind ~= "span") then
                best = e
            end
        end
    end
    if best ~= nil then
        best.part = math.abs(self:xAtTime(best.t1) - x) <= edge and "end" or "body"
    end
    return best
end

-- Úchyt délky vybraného bloku pod kurzorem (kreslí se jen u vybraného), nebo nil; má přednost před značkou bodu trasy.
function E:selectedSpanEndAt(i, x)
    local edge = E.SPAN_EDGE_PX * g_pixelSizeScaledX
    for _, e in ipairs(self:actorSpanList(i)) do
        if math.abs(self:xAtTime(e.t1) - x) <= edge and self:selHas(self:spanObject(i, e)) then
            return e
        end
    end
    return nil
end

-- Věc pro výběr: úsek a pauza = bod trasy j (druh "span" / "wait"), stání = bod křivky k ("stop").
function E:spanObject(i, e)
    local a = self.shot.actors[i]
    if e.kind == "stop" then
        return "stop", speedCurve(a).points[e.k]
    end
    return e.kind, a.points[e.j]
end

-- Blok z vybrané věci (druh, objekt): index herce a záznam z actorSpanList, nebo nil, když už není.
function E:spanFromObject(kind, obj)
    for i, a in ipairs(self.shot.actors) do
        for _, e in ipairs(self:actorSpanList(i)) do
            if e.kind == kind then
                local k2, o2 = self:spanObject(i, e)
                if o2 == obj and k2 == kind then
                    return i, e
                end
            end
        end
    end
    return nil
end

-- Akce a křivky herce od času from (s od startu herce) posune o delta; křivku rychlosti jen s withSpeed.
function E:rippleActor(i, from, delta, withSpeed)
    local actor = self.shot.actors[i]
    if actor == nil or math.abs(delta) < 1e-9 then
        return
    end
    for _, a in ipairs(actor.actions or {}) do
        if a.t >= from - 1e-6 then
            a.t = a.t + delta
        end
    end
    for id, ch in pairs(actor.curves or {}) do
        if withSpeed or id ~= "speed" then
            for _, pt in ipairs(ch.points or {}) do
                if pt.t >= from - 1e-6 then
                    pt.t = pt.t + delta
                end
            end
        end
    end
end

local function touched(self)
    self.actorRt = {}
    S.touch(self.shot)
    self:markDirty()
end

-- Délka stání (bod křivky k = jeho konec) na hold; posune jízdu, akce a křivky za ním.
function E:setStopLength(i, k, hold)
    local actor = self.shot.actors[i]
    local curve = speedCurve(actor)
    if curve == nil or curve.points[k] == nil then
        return
    end
    local p, prev = curve.points[k], curve.points[k - 1]
    local shift = math.max(hold, Ch.MIN_GAP) - (p.t - prev.t)
    local from = p.t
    Ch.shiftFrom(curve, k, shift)
    self:rippleActor(i, from, shift, false)
    touched(self)
end

local function spanStart(self, i, j)
    for _, e in ipairs(self:actorSpanList(i)) do
        if e.kind == "span" and e.j == j then
            return e.t0
        end
    end
    return nil
end

-- Začátek úseku j herce i na čas target (záběr): první úsek posune start herce, další přidá / zkrátí pauzu v bodě j
-- (vozidlo s křivkou rychlosti stání v křivce). Úsek za výstupem z vozidla se posouvá akcí Vystoupit.
function E:moveSpanStart(i, j, target)
    local actor = self.shot.actors[i]
    local current = spanStart(self, i, j)
    if actor == nil or current == nil then
        return
    end
    local delta = target - current
    if math.abs(delta) < 1e-6 then
        return
    end
    if actor.points[j][7] then
        self:showMessage(t("cine_msg_spanExit"))
        return
    end
    local curve = speedCurve(actor)
    if j == 1 then
        local delay = math.max((actor.delay or 0) + delta, -A.earliest(actor), 0)
        if actor.pinActions then
            -- připnuté akce zůstanou v čase záběru
            for _, a in ipairs(actor.actions or {}) do
                a.t = a.t - (delay - (actor.delay or 0))
            end
        end
        actor.delay = delay
    elseif curve ~= nil then
        local delay = actor.delay or 0
        for k = 2, #curve.points do
            if Ch.isStopEnd(curve, k) and math.abs(delay + curve.points[k].t - current) < 0.05 then
                self:setStopLength(i, k, curve.points[k].t - curve.points[k - 1].t + delta)
                return
            end
        end
        if delta > 0.05 then
            local at = current - delay
            local shift = Ch.insertStop(curve, at, delta)
            if shift then
                self:rippleActor(i, at - 1e-3, shift, false)
            end
        end
    else
        -- vozidlo v bodě s pauzou i brzdí a rozjíždí se, takže začátek úseku se posune o víc než pauza: pauza se dopočítá,
        -- ať úsek začne tam, kam ho uživatel táhne; posun kratší, než zabere zastavení, skončí na nejkratší pauze
        self:setPointWait(i, j, nil)
        local free = spanStart(self, i, j)
        if free ~= nil and target > free + 0.05 then
            self:setPointWait(i, j, E.SPAN_MIN_WAIT)
            local now = spanStart(self, i, j)
            if now ~= nil then
                self:setPointWait(i, j, math.max(E.SPAN_MIN_WAIT, E.SPAN_MIN_WAIT + target - now))
            end
        end
    end
    touched(self)
end

-- Délka úseku j: postava rychlostí chůze podle délky, vozidlo rychlostí obou krajních bodů (od rychlostí kmh0
-- na začátku tažení a délky dur0); s křivkou rychlosti nejde. Akce za úsekem se posunou o změnu příjezdu.
function E:setSpanDuration(i, j, dur, base)
    local actor = self.shot.actors[i]
    if actor == nil or actor.points[j + 1] == nil then
        return
    end
    if speedCurve(actor) ~= nil then
        self:showMessage(t("cine_msg_spanCurve"))
        return
    end
    local before = self:routePointTime(i, j + 1)
    local p1, p2 = actor.points[j], actor.points[j + 1]
    if Pe.isPerson(actor) then
        Pe.setSpeed(p1, base.dur0 * base.kmh0[1] / math.max(dur, E.SPAN_MIN))
    else
        -- rychlost se mezi body mění plynule, takže rychlost bodu j by změnila i předchozí úsek (a posunula začátek tohoto):
        -- nejdřív jen rychlost koncového bodu, a teprve když nestačí, obou. Rozjezd a brzdění se se rychlostí nemění
        -- úměrně, násobek se dopočítá po krocích.
        dur = math.max(dur, E.SPAN_MIN)
        local function solve(both)
            local f = 1
            local now = nil
            for _ = 1, 10 do
                p2[3] = M.clamp(base.kmh0[2] * f, 1, 80)
                if both then
                    p1[3] = M.clamp(base.kmh0[1] * f, 1, 80)
                end
                now = self:spanBase(i, j)
                if now == nil or math.abs(now.dur0 - dur) < 0.02 then
                    break
                end
                f = f * (now.dur0 / dur) ^ (both and 1 or 2)
            end
            return now ~= nil and math.abs(now.dur0 - dur) < 0.05
        end
        p1[3] = base.kmh0[1]
        if not solve(false) then
            solve(true)
        end
    end
    self.actorRt = {}
    S.touch(self.shot)
    local after = self:routePointTime(i, j + 1)
    if before ~= nil and after ~= nil then
        self:rippleActor(i, before - (actor.delay or 0), after - before, false)
    end
    touched(self)
end

-- Výchozí stav pro tažení / krok délky úseku: délka a rychlosti krajních bodů.
function E:spanBase(i, j)
    local actor = self.shot.actors[i]
    for _, e in ipairs(self:actorSpanList(i)) do
        if e.kind == "span" and e.j == j then
            local function kmh(p)
                if Pe.isPerson(actor) then
                    return p[3] or Pe.WALK_KMH
                end
                return p[3] or actor.speed or E.ACTOR_SPEED_DEFAULT
            end
            return { dur0 = e.t1 - e.t0, kmh0 = { kmh(actor.points[j]), kmh(actor.points[j + 1]) }, t0 = e.t0, t1 = e.t1 }
        end
    end
    return nil
end

-- Smaže stání z křivky (bod k = konec stání): vozidlo projede bez zastavení, jízda za ním se posune zpět.
function E:removeCurveStop(i, k)
    local actor = self.shot.actors[i]
    local curve = speedCurve(actor)
    if curve == nil or not Ch.isStopEnd(curve, k) then
        return
    end
    local pts = curve.points
    local before, after = pts[k - 2], pts[k + 1]
    if before ~= nil and after ~= nil and math.abs(before.v - after.v) < 0.5 then
        -- brzdění, stání a rozjezd z Ch.insertStop pryč celé (i bod začátku brzdění, ten přidalo zastavení)
        local dur = after.t - before.t
        local from = after.t
        for _ = 1, 4 do
            table.remove(pts, k - 2)
        end
        for idx = k - 2, #pts do
            pts[idx].t = pts[idx].t - dur
        end
        self:rippleActor(i, from, -dur, false)
    else
        local hold = pts[k].t - pts[k - 1].t
        local from = pts[k].t
        table.remove(pts, k)
        table.remove(pts, k - 1)
        self:rippleActor(i, from, -hold, false)
    end
    touched(self)
end

-- Smaže blok: úsek = bod na jeho konci (trasa vede rovnou dál), pauzu, stání.
function E:deleteSpanEntry(i, e)
    if e.kind == "wait" then
        self:setPointWait(i, e.j, nil)
        touched(self)
    elseif e.kind == "stop" then
        self:removeCurveStop(i, e.k)
    elseif e.kind == "span" then
        local actor = self.shot.actors[i]
        if actor.points[e.j + 1] ~= nil and actor.points[e.j + 1][7] then
            self:showMessage(t("cine_msg_exitPoint"))
            return
        end
        if #actor.points <= 2 and e.j == 1 then
            -- jediný úsek: zůstane start
            table.remove(actor.points, 2)
        else
            table.remove(actor.points, e.j + 1)
        end
        touched(self)
    end
end

-- Vybrané bloky jízdy: { i, e } pro každý, který ještě existuje (od konce trasy, ať mazání neposouvá indexy).
function E:selectedSpans()
    local list = {}
    for _, entry in ipairs(self.sel or {}) do
        if entry.kind == "span" or entry.kind == "wait" or entry.kind == "stop" then
            local found = self:selResolve({ entry })[1]
            if found ~= nil then
                local i, e = self:spanFromObject(entry.kind, found.obj)
                if i ~= nil then
                    list[#list + 1] = { i = i, e = e }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.i ~= b.i then
            return a.i > b.i
        end
        return a.e.t0 > b.e.t0
    end)
    return list
end

-- Delete s vybranými bloky jízdy (a ničím jiným): smaže je; true, když se něco smazalo.
function E:deleteSelectedSpans()
    local list = self:selectedSpans()
    if #list == 0 or #list ~= #(self.sel or {}) then
        return false
    end
    self:pushUndo()
    for _, item in ipairs(list) do
        self:deleteSpanEntry(item.i, item.e)
    end
    self:selClear()
    return true
end

-- Rozdělí úsek herce i v čase tm novým bodem trasy (rychlost / chůze i podlaha jako v tom místě).
function E:splitSpanAt(i, tm)
    self:insertRoutePoint(i, tm)
end

-- Tažení bloku: úsek posouvá začátek, jeho konec mění délku, pauza a stání délku. Krok po desetinách, Shift jemně.
function E:dragSpan(drag, x)
    local dt = self:timeAtX(x) - drag.grab
    if not E.isShift() then
        dt = math.floor(dt * 10 + 0.5) / 10
    end
    if not drag.moved then
        if math.abs(dt) < 1e-6 or math.abs(self:xAtTime(drag.grab + dt) - self:xAtTime(drag.grab)) < E.DRAG_SLOP_PX * g_pixelSizeScaledX then
            return
        end
        self:pushUndo()
        drag.moved = true
    end
    local e, i = drag.entry, drag.actor
    local actor = self.shot.actors[i]
    if e.kind == "wait" then
        local wait = math.max(drag.len0 + dt, 0)
        self:setPointWait(i, e.j, wait >= 0.05 and wait or nil)
        touched(self)
        self:showMessage(string.format(t("cine_msg_pauseLength"), e.j, wait))
    elseif e.kind == "stop" then
        self:setStopLength(i, e.k, drag.len0 + dt)
        local curve = speedCurve(actor)
        self:showMessage(string.format(t("cine_msg_stopLength"), curve.points[e.k].t - curve.points[e.k - 1].t))
    elseif drag.part == "end" then
        local dur = math.max(drag.base.dur0 + dt, E.SPAN_MIN)
        self:setSpanDuration(i, e.j, dur, drag.base)
        local now = self:spanBase(i, e.j)
        if now ~= nil then
            self:showMessage(string.format(t("cine_msg_spanLength"), e.j, now.dur0))
        end
    else
        self:moveSpanStart(i, e.j, drag.base.t0 + dt)
        local now = self:spanBase(i, e.j)
        if now ~= nil then
            self:showMessage(string.format(t("cine_msg_spanStart"), e.j, now.t0))
        end
    end
end

-- Klik na blok v řádku herce: vybere ho (Shift přidá) a připraví tažení. false mimo bloky a u vybrané celé jízdy (ta se
-- pak táhne celá, se skupinou výběru).
function E:spanMouseDown(i, x, toggle)
    local e = self:selectedSpanEndAt(i, x)
    if e ~= nil then
        e.part = "end"
    else
        e = self:spanAtScreen(i, x)
    end
    if e == nil or (not toggle and self:selHas("drive", self.shot.actors[i])) then
        return false
    end
    local kind, obj = self:spanObject(i, e)
    local reduce = self:clickSelect(kind, obj, toggle)
    if toggle then
        return true
    end
    local drag = { kind = "span", actor = i, entry = e, part = e.part, grab = self:timeAtX(x), reduce = reduce }
    if e.kind == "span" then
        drag.base = self:spanBase(i, e.j)
    else
        drag.len0 = e.t1 - e.t0
    end
    self.drag = drag
    return true
end
