-- Panel V: kanály = hodnoty s rozsahem, které jde řídit křivkou v čase (zoom kamery, rychlost vozidla od 0 do maxima stroje,
-- osy ramen a výsuvů). Vlevo seznam kanálů (očičko = zobrazení křivky, klik = výběr), vpravo graf vybraného kanálu s
-- ovládacími body (každý má režim: úsečky / skokově / křivka), nahoře značky naklikaných bodů trasy nebo keyframů.
-- Data: owner.curves[id] = kanál z CinemaChannels (owner = záběr pro kameru, herec pro vozidlo); čas kanálů vozidla je
-- od startu jízdy (bez zpoždění herce).

local E = CinemaEditorScreen
local M = CinemaMath
local S = CinemaShot
local W = CinemaWorld
local R = CinemaRoute
local Ch = CinemaChannels

E.CH_ROW = 0.0185
E.CH_STRIP_H = 0.03
E.CH_POINT_HIT_PX = 12

local function t(key)
    return g_i18n:getText(key)
end

E.CH_MODE_TEXT = { linear = "cine_ch_mode_linear", step = "cine_ch_mode_step", smooth = "cine_ch_mode_smooth" }

---------------------------------------------------------------------------------------------------
-- seznam kanálů

-- Plochý seznam: záhlaví skupin (header = true) a kanály { key, owner, id, kind, label, unit, min, max, … }.
-- Sestavuje se jednou za snímek (osy vozidel se čtou z herních objektů).
function CinemaEditorScreen:channelList()
    if self.chCache ~= nil and self.chCache.time == g_time and self.chCache.shot == self.shot then
        return self.chCache.list
    end
    local shot = self.shot
    local list = {}
    list[#list + 1] = { header = true, owner = "cam", label = t("cine_row_camera") }
    list[#list + 1] = { key = "cam:zoom", owner = "cam", id = "zoom", kind = "zoom", label = t("cine_ch_zoom"), unit = "mm",
        min = M.FOCAL_MIN, max = M.FOCAL_MAX }
    list[#list + 1] = { key = "cam:speed", owner = "cam", id = "speed", kind = "camspeed", label = t("cine_ch_camSpeed"), unit = "m/s" }
    if #shot.focus > 0 then
        -- místo cíle bodu zájmu v obraze: 0 = střed, ±1 = kraj
        list[#list + 1] = { key = "cam:aimX", owner = "cam", id = "aimX", kind = "framing", axis = "ox", label = t("cine_ch_aimX"),
            unit = "", min = -1, max = 1 }
        list[#list + 1] = { key = "cam:aimY", owner = "cam", id = "aimY", kind = "framing", axis = "oy", label = t("cine_ch_aimY"),
            unit = "", min = -1, max = 1 }
    end
    for i, a in ipairs(shot.actors) do
        local entries = a.start ~= nil and a.start.entries or {}
        local rootVehicle = entries[1] ~= nil and W.find(entries[1].uid) or nil
        list[#list + 1] = { header = true, owner = i, label = a.name or "?" }
        -- postava křivku rychlosti nemá: chodí, nebo běží (menu bodu trasy), stojí pauzou v bodě
        if not CinemaPerson.isPerson(a) and R.plan(a) ~= nil then
            list[#list + 1] = { key = string.format("a%d:speed", i), owner = i, id = "speed", kind = "speed", label = t("cine_ch_speed"),
                unit = "km/h", min = 0, max = W.maxSpeedKmh(rootVehicle) }
        end
        -- postava s rekvizitou: posun rekvizity proti výchozímu místu v ruce
        if CinemaPerson.isPerson(a) then
            local carries = false
            for _, action in ipairs(a.actions or {}) do
                carries = carries or action.kind == "carry"
            end
            if carries then
                for _, id in ipairs(CinemaPerson.CARRY_CURVES) do
                    list[#list + 1] = { key = string.format("a%d:%s", i, id), owner = i, id = id, kind = "carry",
                        label = t("cine_ch_" .. id), unit = "m", min = -2, max = 2 }
                end
                for _, id in ipairs(CinemaPerson.CARRY_TURNS) do
                    list[#list + 1] = { key = string.format("a%d:%s", i, id), owner = i, id = id, kind = "carry",
                        label = t("cine_ch_" .. id), unit = "°", min = -180, max = 180 }
                end
            end
        end
        for e, entry in ipairs(entries) do
            local v = W.find(entry.uid)
            if v ~= nil then
                for _, def in ipairs(W.toolAxes(v)) do
                    local label = def.label
                    if #entries > 1 then
                        label = W.name(v) .. " - " .. label
                    end
                    list[#list + 1] = { key = string.format("a%d:tool:%d:%d", i, e, def.index), owner = i,
                        id = string.format("tool:%d:%d", e, def.index), kind = "tool", label = label, unit = def.unit,
                        min = def.min, max = def.max, vehicle = v, get = def.get, set = def.set }
                end
            end
        end
    end
    self.chCache = { time = g_time, shot = shot, list = list }
    return list
end

function CinemaEditorScreen:channelByKey(key)
    for _, d in ipairs(self:channelList()) do
        if d.key == key then
            return d
        end
    end
    return nil
end

-- Vybraný kanál; bez výběru ten, který patří aktivnímu řádku na ose (rychlost vozidla, jinak rychlost kamery).
function CinemaEditorScreen:selectedChannel()
    local d = self.chSelected ~= nil and self:channelByKey(self.chSelected) or nil
    if d ~= nil then
        return d
    end
    local wanted = self.activeTarget > 0 and string.format("a%d:speed", self.activeTarget) or "cam:speed"
    return self:channelByKey(wanted) or self:channelByKey("cam:speed")
end

function CinemaEditorScreen:channelOwner(desc)
    return desc.owner == "cam" and self.shot or self.shot.actors[desc.owner]
end

-- Kanál s body (nil, když ještě žádný není); s create ho založí.
function CinemaEditorScreen:channelOf(desc, create)
    local owner = self:channelOwner(desc)
    if owner == nil then
        return nil
    end
    if owner.curves == nil then
        if not create then
            return nil
        end
        owner.curves = {}
    end
    local ch = owner.curves[desc.id]
    if ch == nil and create then
        ch = Ch.new()
        owner.curves[desc.id] = ch
    end
    return ch
end

-- Zpoždění herce: čas kanálu vozidla je od startu jízdy, u části trasy postavy od jejího začátku.
function CinemaEditorScreen:channelDelay(desc)
    if desc.owner == "cam" then
        return 0
    end
    local a = self.shot.actors[desc.owner]
    if desc.leg ~= nil then
        local leg = CinemaPerson.legById(a, desc.leg)
        return leg ~= nil and leg.start or (a.delay or 0)
    end
    return a.delay or 0
end

-- Plán jízdy, kterou kanál rychlosti řídí (u postavy plán části trasy).
function CinemaEditorScreen:channelPlan(desc)
    local a = self.shot.actors[desc.owner]
    if desc.leg ~= nil then
        local leg = CinemaPerson.legById(a, desc.leg)
        return leg ~= nil and R.plan(leg.actor) or nil
    end
    return R.plan(a)
end

-- Kdy (s od začátku záběru) dojede herec s křivkou rychlosti na konec trasy; nil bez křivky nebo když nedojede.
function CinemaEditorScreen:channelFinish(desc)
    if desc.kind ~= "speed" or not Ch.hasPoints(self:channelOf(desc, false)) then
        return nil
    end
    local plan = self:channelPlan(desc)
    return plan ~= nil and plan.reached and self:channelDelay(desc) + plan.total or nil
end

-- Herec, jehož křivku rychlosti kanál řídí (u postavy část trasy).
function CinemaEditorScreen:channelDriver(desc)
    local a = self.shot.actors[desc.owner]
    if desc.leg ~= nil then
        local leg = CinemaPerson.legById(a, desc.leg)
        return leg ~= nil and leg.actor or nil
    end
    return a
end

function CinemaEditorScreen:channelColor(desc)
    if desc.owner == "cam" then
        return E.paletteColor(self:getCamColorIndex())
    end
    return E.paletteColor(self:getActorColorIndex(desc.owner))
end

-- Rozsah kanálu pro zobrazení (rychlost kamery nemá pevný rozsah, bere se podle průběhu).
function CinemaEditorScreen:channelRange(desc)
    if desc.kind == "camspeed" then
        local _, _, vmax = self:getCurveScale()
        return 0, vmax
    end
    return desc.min, desc.max
end

-- Hodnota kanálu v čase t (s od začátku záběru): z bodů, jinak dosavadní průběh bez křivky (stín).
function CinemaEditorScreen:channelValueAt(desc, t)
    local ch = self:channelOf(desc, false)
    local local_t = ch ~= nil and t - self:channelDelay(desc) or nil
    if Ch.isActive(ch, local_t) then
        return Ch.valueAt(ch, local_t)
    end
    if desc.kind == "speed" then
        return self:actorSpeedAt(desc.owner, t) or 0
    elseif desc.kind == "zoom" then
        local _, _, _, _, focal = self:evaluatePose(t, nil)
        return focal
    elseif desc.kind == "camspeed" then
        return self:cameraSpeedAt(t) or 0
    elseif desc.kind == "tool" then
        return desc.get(desc.vehicle)
    elseif desc.kind == "framing" then
        local _, current = S.focusAt(self.shot, t)
        return current ~= nil and current[desc.axis] or 0
    elseif desc.kind == "carry" then
        return 0
    end
    return nil
end

---------------------------------------------------------------------------------------------------
-- úpravy

-- Výchozí body kanálu, který je zatím bez křivky: tvar odpovídá dosavadnímu průběhu, takže se nic nezmění.
function CinemaEditorScreen:materializeChannel(desc)
    local ch = self:channelOf(desc, true)
    if Ch.hasPoints(ch) then
        return ch
    end
    local delay = self:channelDelay(desc)
    if desc.kind == "tool" then
        Ch.addPoint(ch, 0, M.clamp(desc.get(desc.vehicle), desc.min, desc.max))
        return ch
    end
    -- dosavadní průběh se vzorkuje po půl sekundě a zjednoduší na pár bodů, takže tvar zůstane
    local last
    if desc.kind == "speed" then
        local plan = self:channelPlan(desc)
        last = plan ~= nil and plan.total or 1
    else
        last = math.max(S.duration(self.shot), 1)
    end
    local samples = {}
    local steps = math.max(math.ceil(last / 0.5), 1)
    for k = 0, steps do
        local tt = math.min(k * 0.5, last)
        local v = self:channelValueAt(desc, tt + delay)
        samples[#samples + 1] = { t = tt, v = M.clamp(v or desc.min, desc.min, desc.max) }
    end
    local tolerance = desc.kind == "speed" and 1 or (desc.max - desc.min) * 0.01
    for _, p in ipairs(Ch.simplify(samples, tolerance)) do
        Ch.addPoint(ch, p.t, p.v)
    end
    return ch
end

-- Po změně kanálu: přepočet jízdy, náhled os, uložení.
function CinemaEditorScreen:channelChanged(desc)
    S.touch(self.shot)
    if desc.owner ~= "cam" then
        self.actorRt = {}
    end
    self:markDirty()
    self:applyTools(self.playhead)
    if (desc.kind == "zoom" or desc.kind == "framing") and self.topdown == nil then
        self:applyShotPose(self.playhead)
    end
end

-- Hodnota v bodě grafu pod výškou y.
function CinemaEditorScreen:channelValueAtY(desc, y)
    local _, _, _, gy0, gy1 = self:chGeometry()
    local lo, hi = self:channelRange(desc)
    local v = lo + (y - gy0) / (gy1 - gy0) * (hi - lo)
    local step = (hi - lo) / 100
    if desc.kind == "speed" then
        step = E.isShift() and 1 or self.speedStep
    elseif not E.isShift() then
        step = (hi - lo) / 100
    else
        step = (hi - lo) / 1000
    end
    return M.clamp(math.floor(v / step + 0.5) * step, lo, hi)
end

function CinemaEditorScreen:chSnapTime(t)
    if E.isShift() then
        return math.max(t, 0)
    end
    return math.max(math.floor(t * 10 + 0.5) / 10, 0)
end

-- Nový bod ve vybraném kanálu v čase t (s od začátku záběru) s hodnotou v. Vrací index.
function CinemaEditorScreen:addChannelPoint(desc, t, v, mode)
    local ch = self:materializeChannel(desc)
    local local_t = math.max(t - self:channelDelay(desc), 0)
    local finish = self:channelFinish(desc)
    if desc.kind == "speed" and #ch.points >= 2 and (local_t > ch.points[#ch.points].t - Ch.MIN_GAP
        or (finish ~= nil and t > finish - Ch.MIN_GAP)) then
        -- za dojezdem na konec trasy rychlost nic neřídí
        self:showMessage(g_i18n:getText("cine_msg_speedPastEnd"))
        return nil
    end
    local index = Ch.addPoint(ch, local_t, M.clamp(v, desc.min, desc.max), mode)
    self.chPoint = { key = desc.key, index = index }
    self:channelChanged(desc)
    return index
end

function CinemaEditorScreen:removeChannelPoint(desc, index)
    local ch = self:channelOf(desc, false)
    if ch == nil or ch.points[index] == nil then
        return
    end
    if desc.kind == "speed" and (index == 1 or index == #ch.points) then
        self:showMessage(g_i18n:getText("cine_msg_speedEndsFixed"))
        return
    end
    self:pushUndo()
    Ch.removePoint(ch, index)
    self.chPoint = nil
    self:channelChanged(desc)
end

-- Zruší křivku kanálu (u rychlosti se vrátí rychlosti naklikaných bodů trasy).
function CinemaEditorScreen:clearChannel(desc)
    local owner = self:channelOwner(desc)
    if owner == nil or owner.curves == nil or owner.curves[desc.id] == nil then
        return
    end
    self:pushUndo()
    owner.curves[desc.id] = nil
    self.chPoint = nil
    self:channelChanged(desc)
end

function CinemaEditorScreen:toggleChannelHidden(desc)
    local ch = self:channelOf(desc, true)
    self:pushUndo()
    ch.hidden = not ch.hidden or nil
    self:markDirty()
end

-- Rychlost úseku trasy vozidla i s křivkou v čase: body křivky mezi časy from a to se posunou o delta km/h
-- (bez bodu v úseku se přidá bod uprostřed). Vrací true, když šlo o vozidlo s křivkou rychlosti.
function CinemaEditorScreen:shiftSpeedCurve(i, from, to, delta)
    local a = self.shot.actors[i]
    local desc = self:channelByKey(string.format("a%d:speed", i))
    -- postava: křivka té části trasy, do které úsek patří (from a to jsou od startu herce)
    if CinemaPerson.isPerson(a) then
        for _, d in ipairs(self:channelList()) do
            if d.owner == i and d.leg ~= nil and self:channelDelay(d) <= from + (a.delay or 0) + 1e-6 then
                desc = d
            end
        end
        if desc ~= nil then
            local shift = self:channelDelay(desc) - (a.delay or 0)
            from, to = from - shift, to - shift
        end
    end
    -- (postava bez křivky své části mění rychlost bodů, ne křivku jiné části)
    local ch = desc ~= nil and self:channelOf(desc, false)
        or (not CinemaPerson.isPerson(a) and a ~= nil and a.curves ~= nil and a.curves.speed or nil)
    if not Ch.hasPoints(ch) then
        return false
    end
    local lo, hi = 0, desc ~= nil and desc.max or W.DEFAULT_MAX_KMH
    self:pushUndo()
    local touched = false
    for _, p in ipairs(ch.points) do
        if p.t >= from - 1e-6 and p.t <= to + 1e-6 then
            p.v = M.clamp(p.v + delta, lo, hi)
            touched = true
        end
    end
    if not touched then
        local mid = (from + to) * 0.5
        Ch.addPoint(ch, mid, M.clamp((Ch.valueAt(ch, mid) or 0) + delta, lo, hi))
    end
    S.touch(self.shot)
    self.actorRt = {}
    self:markDirty()
    return true
end

---------------------------------------------------------------------------------------------------
-- osy vozidel při přehrávání a náhledu

-- Zapíše do vozidel hodnoty os podle křivek v čase t (s od začátku záběru); původní polohy si pamatuje pro návrat.
function CinemaEditorScreen:applyTools(t)
    local any = false
    for _, d in ipairs(self:channelList()) do
        if d.kind == "tool" then
            local ch = self:channelOf(d, false)
            local localT = t - self:channelDelay(d)
            if Ch.isActive(ch, localT) then
                any = true
                self.toolOriginal = self.toolOriginal or {}
                if self.toolOriginal[d.key] == nil then
                    self.toolOriginal[d.key] = { desc = d, value = d.get(d.vehicle) }
                end
                local value = M.clamp(Ch.valueAt(ch, localT), d.min, d.max)
                local last = self.toolOriginal[d.key].last
                if last == nil or math.abs(last - value) > 1e-4 then
                    self.toolOriginal[d.key].last = value
                    pcall(d.set, d.vehicle, value)
                end
            elseif Ch.hasPoints(ch) and localT < ch.points[1].t and self.toolOriginal ~= nil and self.toolOriginal[d.key] ~= nil
                and self.toolOriginal[d.key].last ~= nil then
                -- před prvním bodem osa do věci nezasahuje: po přeskoku zpět se vrátí do původní polohy; za posledním bodem zůstane
                self.toolOriginal[d.key].last = nil
                pcall(d.set, d.vehicle, self.toolOriginal[d.key].value)
            end
        end
    end
    return any
end

-- Vrátí osy vozidel do polohy před úpravou nebo přehráním.
function CinemaEditorScreen:restoreTools()
    for _, saved in pairs(self.toolOriginal or {}) do
        pcall(saved.desc.set, saved.desc.vehicle, saved.value)
    end
    self.toolOriginal = nil
end

---------------------------------------------------------------------------------------------------
-- geometrie a zásahy myší

-- top panelu, vodorovný rozsah grafu a svislý rozsah plochy grafu.
function CinemaEditorScreen:chGeometry()
    local top = self:getPanelTop()
    return top, E.TRACK_X0, E.TRACK_X1, top + 0.012, top + E.CURVE_HEIGHT - E.CH_STRIP_H - 0.008
end

function CinemaEditorScreen:chVisibleRows()
    return math.floor((E.CURVE_HEIGHT - 0.012) / E.CH_ROW)
end

-- Řádek seznamu (index do channelList) pod bodem a část ("eye" nebo "row").
function CinemaEditorScreen:chRowAt(x, y)
    local top = self:getPanelTop()
    if x >= E.TRACK_X0 - 0.004 then
        return nil
    end
    local k = math.floor((top + E.CURVE_HEIGHT - 0.008 - y) / E.CH_ROW)
    if k < 0 or k >= self:chVisibleRows() then
        return nil
    end
    local index = k + 1 + (self.chScroll or 0)
    local entry = self:channelList()[index]
    if entry == nil then
        return nil
    end
    return index, x <= 0.024 and "eye" or "row"
end

-- Bod vybraného kanálu pod kurzorem, nebo nil.
function CinemaEditorScreen:chPointAt(desc, x, y)
    local ch = self:channelOf(desc, false)
    if not Ch.hasPoints(ch) then
        return nil
    end
    local best, bestDist = nil, E.CH_POINT_HIT_PX * g_pixelSizeScaledX
    local _, _, _, gy0, gy1 = self:chGeometry()
    local lo, hi = self:channelRange(desc)
    local delay = self:channelDelay(desc)
    for i, p in ipairs(ch.points) do
        local px = self:xAtTime(p.t + delay)
        local py = gy0 + (gy1 - gy0) * (p.v - lo) / (hi - lo)
        local dist = math.sqrt((px - x) ^ 2 + ((py - y) / g_screenAspectRatio) ^ 2)
        if dist <= bestDist then
            best, bestDist = i, dist
        end
    end
    return best
end

-- Zásah v panelu V: { kind = "chEye" | "chRow" | "chList" | "chPoint" | "chGraph" | "routePoint" | "key" | "curveKey" | "curveHandle" | "curve" }.
function CinemaEditorScreen:hitChannelPanel(x, y)
    local top = self:getPanelTop()
    if x < E.TRACK_X0 - 0.004 then
        local index, part = self:chRowAt(x, y)
        if index == nil then
            return { kind = "chList" }
        end
        local entry = self:channelList()[index]
        if entry.header then
            return { kind = "chList" }
        end
        return { kind = part == "eye" and "chEye" or "chRow", key = entry.key }
    end
    local desc = self:selectedChannel()
    -- pruh značek nahoře: body trasy vozidla, u kamery K-framy Letů
    if y >= top + E.CURVE_HEIGHT - E.CH_STRIP_H then
        local best, bestDist = nil, E.ROUTE_KEY_PX * g_pixelSizeScaledX
        if desc ~= nil and desc.owner ~= "cam" then
            local point = self:routePointAtScreen(desc.owner, x)
            if point ~= nil then
                return { kind = "routePoint", index = desc.owner, point = point }
            end
        elseif desc ~= nil then
            for _, e in ipairs(S.allKeys(self.shot)) do
                local dist = math.abs(self:xAtTime(e.t) - x)
                if dist <= bestDist then
                    best, bestDist = e, dist
                end
            end
            if best ~= nil then
                return { kind = "key", seg = best.seg, index = best.index }
            end
        end
        return { kind = "curve" }
    end
    if desc == nil then
        return { kind = "curve" }
    end
    if desc.kind == "camspeed" then
        local handle = self:curveHandleAt(x, y)
        if handle ~= nil then
            return { kind = "curveHandle", seg = handle.seg, index = handle.index, side = handle.side }
        end
        local hit = self:curveKeyAt(x, y)
        if hit ~= nil then
            return { kind = "curveKey", seg = hit.seg, index = hit.index }
        end
        return { kind = "curve" }
    end
    local index = self:chPointAt(desc, x, y)
    if index ~= nil then
        return { kind = "chPoint", key = desc.key, index = index }
    end
    return { kind = "chGraph", key = desc.key }
end

-- Levé tlačítko v panelu V (kromě značek nahoře, ty obslouží běžné zásahy).
function CinemaEditorScreen:chPanelDown(hit, x, y)
    if hit.kind == "chEye" then
        local desc = self:channelByKey(hit.key)
        if desc ~= nil then
            self:toggleChannelHidden(desc)
        end
    elseif hit.kind == "chRow" then
        local desc = self:channelByKey(hit.key)
        self.chSelected, self.chPoint = hit.key, nil
        if desc ~= nil then
            self:setActiveTarget(desc.owner == "cam" and 0 or desc.owner)
        end
    elseif hit.kind == "chPoint" or hit.kind == "chGraph" then
        local desc = self:channelByKey(hit.key)
        if desc == nil then
            return
        end
        self.chSelected = desc.key
        local index = hit.index
        if hit.kind == "chGraph" then
            self:pushUndo()
            index = self:addChannelPoint(desc, self:chSnapTime(self:timeAtX(x)), self:channelValueAtY(desc, y))
            if index == nil then
                table.remove(self.undoStack)
                return
            end
        else
            self.chPoint = { key = desc.key, index = index }
        end
        self.drag = { kind = "chPoint", key = desc.key, index = index, moved = hit.kind == "chGraph" }
        local ch = self:channelOf(desc, false)
        self:setPlayhead(ch.points[index].t + self:channelDelay(desc), self.topdown == nil)
    end
end

-- Tažení bodu kanálu: čas i hodnota.
function CinemaEditorScreen:chPanelDrag(x, y)
    local drag = self.drag
    local desc = self:channelByKey(drag.key)
    local ch = desc ~= nil and self:channelOf(desc, false) or nil
    if ch == nil or ch.points[drag.index] == nil then
        return
    end
    if not drag.moved then
        self:pushUndo()
        drag.moved = true
    end
    local delay = self:channelDelay(desc)
    local t, v = self:chSnapTime(self:timeAtX(x)) - delay, self:channelValueAtY(desc, y)
    if desc.kind == "speed" then
        -- krajní body rychlosti jsou napevno (R.fitCurveEnd): začátek jen hodnotou, konec (nula při dojezdu) vůbec
        if drag.index == #ch.points then
            return
        elseif drag.index == 1 then
            t = 0
        end
    end
    if desc.kind == "speed" and Ch.isStopEnd(ch, drag.index) then
        -- konec stání: delší nebo kratší stání posune celou další jízdu
        Ch.shiftFrom(ch, drag.index, t - ch.points[drag.index].t)
        self:showMessage(string.format(g_i18n:getText("cine_msg_stopLength"), ch.points[drag.index].t - ch.points[drag.index - 1].t))
    else
        Ch.movePoint(ch, drag.index, t, v)
    end
    self.playhead = ch.points[drag.index].t + delay
    self:channelChanged(desc)
end

function CinemaEditorScreen:chScrollBy(steps)
    local maxScroll = math.max(#self:channelList() - self:chVisibleRows(), 0)
    self.chScroll = M.clamp((self.chScroll or 0) - steps, 0, maxScroll)
end

-- Je kurzor nad seznamem kanálů? (kolečko ho tam posouvá)
function CinemaEditorScreen:isOverChannelList()
    if not self.curves or not self.cursorShown or self.mouseX == nil then
        return false
    end
    local top = self:getPanelTop()
    return self.mouseY > top and self.mouseY <= top + E.CURVE_HEIGHT and self.mouseX < E.TRACK_X0 - 0.004
end

---------------------------------------------------------------------------------------------------
-- menu

function CinemaEditorScreen:openChannelPointMenu(key, index, x, y)
    local desc = self:channelByKey(key)
    local ch = desc ~= nil and self:channelOf(desc, false) or nil
    local p = ch ~= nil and ch.points[index] or nil
    if p == nil then
        return
    end
    local lo, hi = self:channelRange(desc)
    local function change(fn)
        self:pushUndo()
        fn()
        self:channelChanged(desc)
    end
    local items = {}
    local function item(text, action, keepOpen, disabled)
        items[#items + 1] = { text = text, action = action, keepOpen = keepOpen, disabled = disabled }
    end
    for _, mode in ipairs(Ch.MODES) do
        item(function() return (p.mode == mode and "> " or "") .. t(E.CH_MODE_TEXT[mode]) end,
            function() change(function() Ch.setMode(ch, index, mode) end) end, true)
    end
    local step = desc.kind == "speed" and self.speedStep or (hi - lo) / 100
    item(function() return string.format(t("cine_ch_valueUp"), p.v, desc.unit) end,
        function() change(function() p.v = M.clamp(p.v + step, lo, hi) end) end, true)
    item(function() return string.format(t("cine_ch_valueDown"), p.v, desc.unit) end,
        function() change(function() p.v = M.clamp(p.v - step, lo, hi) end) end, true)
    item(t("cine_ch_pointDelete"), function() self:removeChannelPoint(desc, index) end)
    self:openMenu(string.format(t("cine_ch_pointTitle"), desc.label, p.t + self:channelDelay(desc)), items, x, y)
end

function CinemaEditorScreen:openChannelMenu(key, x, y)
    local desc = self:channelByKey(key) or self:selectedChannel()
    if desc == nil or desc.kind == "camspeed" then
        return
    end
    local items = {}
    local at = self:chSnapTime(self:timeAtX(x))
    local value = self:channelValueAtY(desc, y)
    items[#items + 1] = { text = string.format(t("cine_ch_pointAdd"), at), action = function()
        self:pushUndo()
        self:addChannelPoint(desc, at, value)
    end }
    if desc.kind == "speed" then
        items[#items + 1] = { text = string.format(t("cine_ch_stopHere"), at, Ch.STOP_HOLD), action = function()
            self:pushUndo()
            local ch = self:materializeChannel(desc)
            if not Ch.insertStop(ch, at - self:channelDelay(desc), Ch.STOP_HOLD) then
                table.remove(self.undoStack)
                self:showMessage(t("cine_msg_stopStanding"))
                return
            end
            self.chPoint = nil
            self:channelChanged(desc)
        end }
        local driver = self:channelDriver(desc)
        local dead = driver ~= nil and #R.deadCurvePoints(driver) or 0
        items[#items + 1] = { text = string.format(t("cine_ch_trimSpeed"), dead), disabled = dead == 0, action = function()
            self:pushUndo()
            R.trimCurve(driver)
            self.chPoint = nil
            self:channelChanged(desc)
        end }
    end
    items[#items + 1] = { text = t(desc.kind == "speed" and "cine_ch_clearSpeed" or "cine_ch_clear"), action = function() self:clearChannel(desc) end,
        disabled = not Ch.hasPoints(self:channelOf(desc, false)) }
    self:openMenu(desc.label, items, x, y)
end
