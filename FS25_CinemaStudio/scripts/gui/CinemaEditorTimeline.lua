-- Úpravy klipů na časové ose: přichytávání, přesun a kopie výběru (přepsat / vložit), ořez bloků, obdélníkový výběr,
-- mazání (i se zavřením mezery), rozdělení a nahrazení režimu bloku. Pravidla jsou pro všechny bloky stejná:
-- klik vybere (Shift přepne), tažení těla přesune celý výběr, tažení kraje bloku ořízne, Ctrl + tažení kopíruje.
-- K-framy jsou uvnitř bloků: táhnou se jen v rámci svého bloku a s blokem se posouvají, kopírují a mažou.

local E = CinemaEditorScreen
local S = CinemaShot
local M = CinemaMath
local Mo = CinemaModes
local A = CinemaActions
local W = CinemaWorld
local Cam = CinemaCamera

E.SNAP_PX = 8 -- jak blízko (v pixelech) se čas přichytí k okraji jiné věci
E.DRAG_SLOP_PX = 4 -- o kolik se musí kurzor pohnout, aby se z kliknutí stalo tažení

---------------------------------------------------------------------------------------------------
-- přichytávání

local function gridTime(t)
    return math.floor(t * 10 + 0.5) / 10
end

-- Přichytávání je zapnuté (klávesa), dokud se nedrží Shift.
function CinemaEditorScreen:snapEnabled()
    return self.snapOn ~= false and not E.isShift()
end

function CinemaEditorScreen:snapTolerance()
    return E.SNAP_PX * g_pixelSizeScaledX / (E.TRACK_X1 - E.TRACK_X0) * self:getViewSpan()
end

local function excluded(exclude, kind, id)
    return exclude ~= nil and exclude[E.itemKey(kind, id)] == true
end

-- Časy, ke kterým se tažení přichytává: začátek, playhead (bez noPlayhead) a okraje a K-framy všech věcí kromě těch v exclude.
-- S blocks = táhne se blok kamery: kraje ostatních bloků jsou posunuté o MIN_GAP ven, aby se přichycený blok souseda
-- dotkl, a ne ho ořízl (bloky se nesmí dotýkat).
function CinemaEditorScreen:snapTargets(exclude, noPlayhead, blocks)
    local shot = self.shot
    local list = { 0 }
    if not noPlayhead then
        list[2] = self.playhead
    end
    local gap = blocks and S.MIN_GAP or 0
    for _, seg in ipairs(shot.segments) do
        if not excluded(exclude, "block", seg.id) then
            local finish = S.segmentEnd(seg)
            list[#list + 1] = seg.t - gap
            list[#list + 1] = finish + gap
            for _, at in ipairs(S.kframeTimes(seg)) do
                if not blocks or (at > 1e-6 and seg.t + at < finish - 1e-6) then
                    list[#list + 1] = seg.t + at
                end
            end
        end
    end
    for _, f in ipairs(shot.focus) do
        if not excluded(exclude, "focus", S.uid(f)) then
            list[#list + 1] = f.t
        end
    end
    for i, a in ipairs(shot.actors) do
        local delay = a.delay or 0
        if not excluded(exclude, "drive", S.uid(a)) then
            list[#list + 1] = delay
            list[#list + 1] = self:actorEnd(i)
        end
        for _, action in ipairs(a.actions or {}) do
            if not excluded(exclude, "action", S.uid(action)) then
                list[#list + 1] = delay + action.t
                list[#list + 1] = delay + A.endTime(action)
            end
        end
    end
    return list
end

-- Posun k nejbližšímu cíli pro některý z časů; vrací posun a čas cíle, nebo 0 a nil, když nic není poblíž.
function CinemaEditorScreen:snapOffset(times, targets)
    local tol = self:snapTolerance()
    local best, bestTarget
    for _, t in ipairs(times) do
        for _, g in ipairs(targets) do
            local d = g - t
            if math.abs(d) <= tol and (best == nil or math.abs(d) < math.abs(best)) then
                best, bestTarget = d, g
            end
        end
    end
    return best or 0, bestTarget
end

-- Posun dt věci s časy times po přichycení (jinak po zaokrouhlení začátku na desetiny; s Shiftem bez úprav).
function CinemaEditorScreen:snapMove(times, dt, targets)
    self.snapGuide = nil
    if E.isShift() then
        return dt
    end
    if self.snapOn ~= false then
        local shifted = {}
        for i, t in ipairs(times) do
            shifted[i] = t + dt
        end
        local offset, target = self:snapOffset(shifted, targets)
        if target ~= nil then
            self.snapGuide = target
            return dt + offset
        end
    end
    return gridTime(times[1] + dt) - times[1]
end

-- Čas t po přichycení (kraj bloku při ořezu).
function CinemaEditorScreen:snapTime(t, targets)
    return t + self:snapMove({ t }, 0, targets)
end

---------------------------------------------------------------------------------------------------
-- výběr kliknutím a obdélníkem

-- Klik na věc: vybere ji, Shift ji přidá nebo ubere. Věc, která je už ve vícenásobném výběru, ho při prostém kliku drží
-- (aby šla táhnout celá skupina); vrací ji, aby ji puštění bez tažení vybralo samotnou.
function CinemaEditorScreen:clickSelect(kind, obj, toggle)
    if toggle then
        self:selToggle(kind, obj)
        return nil
    end
    if self:selHas(kind, obj) and self:selCount() > 1 then
        return { kind = kind, obj = obj }
    end
    self:selSet(kind, obj)
    return nil
end

-- Čas začátku a konce věci na ose (ve vteřinách záběru).
function CinemaEditorScreen:clipTimes(e)
    local kind = e.kind
    if kind == "block" then
        return e.obj.t, S.segmentEnd(e.obj)
    elseif kind == "action" then
        local delay = e.owner.delay or 0
        return delay + e.obj.t, delay + A.endTime(e.obj)
    elseif kind == "drive" then
        return e.obj.delay or 0, self:actorEnd(e.index)
    elseif kind == "part" then
        return e.obj.t0, e.obj.t1
    elseif kind == "mark" then
        local t = e.owner.t + e.obj.u * (e.owner.track.duration or 0)
        return t, t
    elseif kind == "key" then
        return e.owner.t + e.obj.t, e.owner.t + e.obj.t
    end
    return e.obj.t, e.obj.t
end

-- Věci, jejichž obdélník na ose protíná čas t0..t1 a výšku y0..y1 (obrazovka): { kind, id }.
function CinemaEditorScreen:clipsInRect(t0, t1, y0, y1)
    local shot, list = self.shot, {}
    local function inY(ry, rh)
        return y1 >= ry and y0 <= ry + rh
    end
    local function add(kind, obj)
        list[#list + 1] = { kind = kind, id = self:selIdOf(kind, obj) }
    end
    if inY(self:getCamRowY(), E.TRACK_H) then
        for _, seg in ipairs(shot.segments) do
            if seg.t <= t1 and S.segmentEnd(seg) >= t0 then
                add("block", seg)
            end
        end
    end
    if self:isFocusRowShown() and inY(self:getFocusRowY(), E.ROW_H) then
        for _, f in ipairs(shot.focus) do
            if f.t >= t0 and f.t <= t1 then
                add("focus", f)
            end
        end
    end
    for i, a in ipairs(shot.actors) do
        if self:isActorShown(i) then
            if inY(self:getActorRowY(i), E.ROW_H) and (a.delay or 0) <= t1 and self:actorEnd(i) >= t0 then
                add("drive", a)
            end
            for k, kind in ipairs(self:getActorLanes(i)) do
                if inY(self:getLaneY(i, k), E.LANE_H) then
                    local delay = a.delay or 0
                    for _, action in ipairs(a.actions or {}) do
                        if action.kind == kind and delay + action.t <= t1 and delay + A.endTime(action) >= t0 then
                            add("action", action)
                        end
                    end
                end
            end
        end
    end
    return list
end

function CinemaEditorScreen:beginMarquee(x, y, toggle)
    local base = {}
    if toggle then
        for _, e in ipairs(self:selEntries()) do
            base[#base + 1] = { kind = e.kind, id = e.id }
        end
    end
    self.drag = { kind = "marquee", x0 = x, y0 = y, x = x, y = y, add = toggle, base = base, t0 = self:timeAtX(x) }
end

function CinemaEditorScreen:dragMarquee(x, y)
    local drag = self.drag
    if not drag.moved then
        if math.abs(x - drag.x0) < E.DRAG_SLOP_PX * g_pixelSizeScaledX and math.abs(y - drag.y0) < E.DRAG_SLOP_PX * g_pixelSizeScaledY then
            return
        end
        drag.moved = true
    end
    drag.x, drag.y = x, y
    local t0, t1 = self:timeAtX(math.min(drag.x0, x)), self:timeAtX(math.max(drag.x0, x))
    local picked = self:clipsInRect(t0, t1, math.min(drag.y0, y), math.max(drag.y0, y))
    local sel, seen = {}, {}
    for _, list in ipairs({ drag.base, picked }) do
        for _, entry in ipairs(list) do
            local key = E.itemKey(entry.kind, entry.id)
            if not seen[key] then
                seen[key] = true
                sel[#sel + 1] = entry
            end
        end
    end
    self.sel = sel
end

-- Puštění tlačítka myši po tažení v panelu: dokončí výběr obdélníkem, kopii a prosté kliknutí.
function CinemaEditorScreen:finishDrag()
    local drag = self.drag
    self.snapGuide = nil
    if drag == nil then
        return
    end
    if drag.kind == "clip" or drag.kind == "span" then
        if not drag.moved and drag.reduce ~= nil then
            self:selSet(drag.reduce.kind, drag.reduce.obj)
        elseif drag.moved and drag.copies ~= nil and #drag.copies > 0 then
            self.sel = drag.copies
        end
    elseif drag.kind == "row" then
        if drag.moved and drag.drop ~= nil then
            self:moveRow(drag.key, drag.drop)
        elseif not drag.moved and drag.click ~= nil then
            drag.click(self)
        end
    elseif drag.kind == "marquee" and not drag.moved then
        if not drag.add then
            self:selClear()
        end
        self:followPlayhead(drag.t0)
    elseif drag.kind == "scrub" and drag.stash ~= nil then
        local st = drag.stash
        self.targetFocal = st.focal
        Cam.setPose(self.cam, st.x, st.y, st.z, M.quatFromYawPitchRoll(st.yaw, st.pitch, st.roll), st.focal)
        self.syncedPose = st.synced
    end
    self.drag = nil
end

---------------------------------------------------------------------------------------------------
-- přesun a kopie výběru

-- Věci výběru, které jdou přesouvat v čase (K-framy a značky se táhnou uvnitř bloku).
local function movableItems(self, kind, obj, forCopy)
    local items, primary = {}, nil
    local entries = self:selEntries()
    local drives = {}
    for _, e in ipairs(entries) do
        if e.kind == "drive" then
            drives[e.obj] = true
        end
    end
    for _, e in ipairs(entries) do
        -- akce vozidla vybraného celého se posunou s jízdou, samostatně by se posunuly dvakrát; jízda se nekopíruje
        local skip = (e.kind == "action" and not forCopy and drives[e.owner]) or (e.kind == "drive" and forCopy)
        if not skip and (e.kind == "block" or e.kind == "part" or e.kind == "focus" or e.kind == "action" or e.kind == "drive") then
            local t0, t1 = self:clipTimes(e)
            local item = { kind = e.kind, id = e.id, t0 = t0, t1 = t1, local0 = (e.kind == "action" and e.obj.t) or (e.kind == "drive" and (e.obj.delay or 0)) or t0 }
            if e.kind == "drive" and not e.obj.pinActions then
                item.earliest = A.earliest(e.obj)
            end
            if e.kind == "drive" and e.obj.pinActions then
                -- akce vozidla zůstanou na místě (v čase záběru), takže se jejich čas od startu vozidla přepočte
                item.pinned = {}
                for _, action in ipairs(e.obj.actions or {}) do
                    item.pinned[#item.pinned + 1] = { action = action, t0 = action.t }
                end
            end
            items[#items + 1] = item
            if e.kind == kind and e.id == self:selIdOf(kind, obj) then
                primary = item
            end
        end
    end
    return items, primary
end

local function excludeSet(items)
    local set = {}
    for _, item in ipairs(items) do
        set[E.itemKey(item.kind, item.id)] = true
    end
    return set
end

-- Začne tažení výběru za věc kind / obj; reduce = věc, která se puštěním bez tažení vybere samotná.
function CinemaEditorScreen:beginClipDrag(x, kind, obj, reduce)
    local items, primary = movableItems(self, kind, obj)
    if primary == nil then
        return
    end
    self.drag = { kind = "clip", items = items, primary = primary, grab = self:timeAtX(x), x0 = x, reduce = reduce, exclude = excludeSet(items) }
end

-- Nejmenší a největší posun, který nic nepřehodí přes jiný bod zájmu a nepošle nic před nulu (bloky se přepíšou nebo vloží).
function CinemaEditorScreen:clampClipMove(drag, dt)
    local lo, hi = -math.huge, math.huge
    local base = drag.base
    local selectedFocus = {}
    for _, item in ipairs(drag.items) do
        -- akce smí i před start vozidla, ne ale před začátek záběru; s jízdou se posouvají i její akce
        if item.kind == "action" or item.kind == "drive" then
            lo = math.max(lo, -item.t0 - (item.kind == "drive" and math.min(item.earliest or 0, 0) or 0))
        else
            lo = math.max(lo, -item.local0)
        end
        if item.kind == "focus" then
            selectedFocus[item.id] = true
        end
    end
    local function limits(list, isSelected)
        for i, entry in ipairs(list) do
            if isSelected(entry) and entry.moving then
                for j = i - 1, 1, -1 do
                    if not isSelected(list[j]) then
                        lo = math.max(lo, list[j].t + S.MIN_GAP - entry.t)
                        break
                    end
                end
                for j = i + 1, #list do
                    if not isSelected(list[j]) then
                        hi = math.min(hi, list[j].t - S.MIN_GAP - entry.t)
                        break
                    end
                end
            end
        end
    end
    for _, f in ipairs(base.focus) do
        f.moving = selectedFocus[S.uid(f)] == true
    end
    limits(base.focus, function(f)
        return f.moving
    end)
    for _, f in ipairs(base.focus) do
        f.moving = nil
    end
    if lo > hi then
        return 0
    end
    return M.clamp(dt, lo, hi)
end

-- Úsek blokem moved zbytek jiných bloků ořízne nebo smaže (skip = bloky, které se přesouvají spolu s ním).
function CinemaEditorScreen:clearSpanForNewBlock(seg, skip)
    local shot = self.shot
    local t0, t1 = seg.t, S.segmentEnd(seg)
    for i = #shot.segments, 1, -1 do
        local other = shot.segments[i]
        if other.id ~= seg.id and not (skip ~= nil and skip[other.id]) and other.t < t1 - S.KEY_SNAP and S.segmentEnd(other) > t0 + S.KEY_SNAP then
            -- ořezaný blok od nového odstup MIN_GAP, aby se nedotýkaly (dotyk se bere jako překryv)
            if other.t < t0 - S.KEY_SNAP and t0 - S.MIN_GAP - other.t >= S.MIN_SEGMENT then
                S.resizeSegment(shot, other, "end", t0 - S.MIN_GAP)
            elseif other.t >= t0 - S.KEY_SNAP and S.segmentEnd(other) - t1 - S.MIN_GAP >= S.MIN_SEGMENT then
                S.resizeSegment(shot, other, "start", t1 + S.MIN_GAP)
            else
                S.removeSegment(shot, i)
            end
        end
    end
end

-- Vložení: co začíná v rozsahu přesunutých bloků nebo za ním, odskočí doprava o tolik, aby se vešly.
local function openGap(shot, segs, except)
    local lo, hi = math.huge, -math.huge
    for _, seg in ipairs(segs) do
        lo, hi = math.min(lo, seg.t), math.max(hi, S.segmentEnd(seg))
    end
    local first = math.huge
    for _, other in ipairs(shot.segments) do
        if not except.segs[other.id] and other.t >= lo - S.KEY_SNAP then
            first = math.min(first, other.t)
        end
    end
    if first < math.huge and first < hi + S.MIN_GAP then
        S.shiftAfter(shot, lo - S.KEY_SNAP, hi + S.MIN_GAP - first, except)
    end
end

local function stripUids(list)
    for _, item in ipairs(list or {}) do
        item.uid = nil
    end
end

local function copyOf(obj)
    local copy = S.copyTable(obj)
    copy.uid = nil
    stripUids(copy.marks)
    stripUids(copy.keys)
    if copy.track ~= nil then
        stripUids(copy.track.marks)
        stripUids(copy.track.keys)
    end
    return copy
end

-- Úsek from..to (s od začátku bloku) stopy jako nová stopa stejného druhu.
function CinemaEditorScreen:pieceOf(track, from, to)
    if S.hasKeys(track) then
        return S.flightPiece(self.shot, track, from, to)
    end
    return Mo.piece(track, from, to)
end

-- Přesune (nebo zkopíruje) věci drag.items o dt. S drag.base se kamera nejdřív vrátí do stavu před tažením, takže se přepsané
-- bloky při dalším pohybu vrátí. Vozidla (akce, jízdy) se přepočítají z původních časů.
function CinemaEditorScreen:applyClipMove(drag, dt, copy)
    local shot = self.shot
    if drag.base ~= nil then
        S.restore(shot, drag.base, true)
    end
    for _, c in ipairs(drag.actionCopies or {}) do
        for i, action in ipairs(c.actor.actions) do
            if action == c.action then
                table.remove(c.actor.actions, i)
                break
            end
        end
    end
    drag.actionCopies, drag.copies = {}, {}
    if copy and math.abs(dt) < 1e-6 then
        S.touch(shot)
        return
    end
    local byKey = {}
    for _, item in ipairs(drag.items) do
        byKey[E.itemKey(item.kind, item.id)] = item
    end
    for _, item in ipairs(drag.items) do
        for _, p in ipairs(not copy and item.pinned or {}) do
            p.action.t = p.t0 - dt
        end
    end
    local resolved = self:selResolve(drag.items)
    local segs, segIds, focusSet, touchedActors = {}, {}, {}, {}
    for _, e in ipairs(resolved) do
        local item = byKey[E.itemKey(e.kind, e.id)]
        if copy then
            if e.kind == "focus" then
                local c = copyOf(e.obj)
                c.t = e.obj.t + dt
                local index = S.setFocus(shot, c.t, c.target, c.height)
                shot.focus[index].blend = c.blend
                focusSet[shot.focus[index]] = true
                drag.copies[#drag.copies + 1] = { kind = "focus", id = S.uid(shot.focus[index]) }
            elseif e.kind == "block" then
                local seg = { id = S.nextSegmentId(shot), t = e.obj.t + dt, track = copyOf(e.obj.track) }
                S.addSegment(shot, seg)
                segs[#segs + 1] = seg
                segIds[seg.id] = true
                drag.copies[#drag.copies + 1] = { kind = "block", id = seg.id }
            elseif e.kind == "part" then
                local seg = { id = S.nextSegmentId(shot), t = e.obj.t0 + dt,
                    track = self:pieceOf(e.owner.track, e.obj.t0 - e.owner.t, e.obj.t1 - e.owner.t) }
                S.addSegment(shot, seg)
                segs[#segs + 1] = seg
                segIds[seg.id] = true
                drag.copies[#drag.copies + 1] = { kind = "block", id = seg.id }
            elseif e.kind == "action" then
                local c = copyOf(e.obj)
                c.t = item.local0 + dt
                A.add(e.owner, c)
                drag.actionCopies[#drag.actionCopies + 1] = { actor = e.owner, action = c }
                drag.copies[#drag.copies + 1] = { kind = "action", id = S.uid(c) }
            end
        elseif e.kind == "focus" then
            e.obj.t = e.obj.t + dt
            focusSet[e.obj] = true
        elseif e.kind == "block" then
            e.obj.t = e.obj.t + dt
            segs[#segs + 1] = e.obj
            segIds[e.obj.id] = true
        elseif e.kind == "action" then
            e.obj.t = item.local0 + dt
            touchedActors[e.owner] = true
        elseif e.kind == "drive" then
            e.obj.delay = item.local0 + dt
        end
    end
    for actor in pairs(touchedActors) do
        A.sortByTime(actor)
    end
    if #segs > 0 then
        if self.editMode == "insert" then
            self:splitForInsert(segs, segIds)
            openGap(shot, segs, { segs = segIds, focus = focusSet })
        end
        for _, seg in ipairs(segs) do
            self:clearSpanForNewBlock(seg, segIds)
        end
    end
    S.sortSegments(shot)
    S.touch(shot)
    self.actorRt = {}
    if self.playheadAnywhere then
        self.playhead = math.max(0, drag.primary.t0 + dt)
    end
    if self.topdown == nil then
        self:applyShotPose(self.playhead)
    end
    self:markDirty()
end

function CinemaEditorScreen:dragClip(x)
    local drag = self.drag
    if not drag.moved then
        if math.abs(x - drag.x0) < E.DRAG_SLOP_PX * g_pixelSizeScaledX then
            return
        end
        self:pushUndo()
        drag.moved = true
        drag.base = self.undoStack[#self.undoStack]
        drag.copy = E.isCtrl()
        if not drag.copy and self:selHasKind("part") then
            local mapping = self:materializeParts()
            local primary = drag.primary
            local mapped = primary.kind == "part" and { kind = "block", id = mapping[primary.id] } or { kind = primary.kind, id = primary.id }
            local resolved = self:selResolve({ mapped })[1]
            local items, newPrimary
            if resolved ~= nil then
                items, newPrimary = movableItems(self, resolved.kind, resolved.obj)
            end
            if newPrimary == nil then
                self.drag = nil
                return
            end
            drag.items, drag.primary, drag.exclude = items, newPrimary, excludeSet(items)
            drag.base = S.clone(self.shot)
        end
        local primaryKind = drag.primary.kind
        drag.targets = self:snapTargets(drag.exclude, false, primaryKind == "block" or primaryKind == "part")
    end
    local primary = drag.primary
    local dt = self:snapMove({ primary.t0, primary.t1 }, self:timeAtX(x) - drag.grab, drag.targets)
    self:applyClipMove(drag, self:clampClipMove(drag, dt), drag.copy)
end

-- Duplikuje vybrané věci hned za sebe (za nejposlednější konec výběru).
function CinemaEditorScreen:duplicateSelection()
    local items = movableItems(self, nil, nil, true)
    if #items == 0 then
        self:showMessage(g_i18n:getText("cine_msg_nothingToCopy"))
        return
    end
    local lo, hi = math.huge, -math.huge
    for _, item in ipairs(items) do
        lo, hi = math.min(lo, item.t0), math.max(hi, item.t1)
    end
    self:pushUndo()
    local drag = { items = items, primary = { t0 = lo }, base = nil }
    self:applyClipMove(drag, hi - lo + S.MIN_GAP, true)
    self.sel = drag.copies
    self.playhead = lo
    self:showMessage(g_i18n:getText("cine_msg_duplicated"))
end

---------------------------------------------------------------------------------------------------
-- ořez bloku

function CinemaEditorScreen:beginTrim(x, seg, edge)
    self.drag = { kind = "trim", id = seg.id, edge = edge, x0 = x }
end

-- Tažení kraje bloku: mění jeho začátek nebo konec (druhý konec stojí). Ořez se počítá vždy ze stavu před tažením, takže
-- zkrácení a zpětné natažení Letu nic neztratí; kamera ukazuje snímek na taženém kraji.
function CinemaEditorScreen:dragTrim(x)
    local drag = self.drag
    if not drag.moved then
        if math.abs(x - drag.x0) < E.DRAG_SLOP_PX * g_pixelSizeScaledX then
            return
        end
        self:pushUndo()
        drag.moved = true
        drag.base = self.undoStack[#self.undoStack]
        drag.targets = self:snapTargets({ [E.itemKey("block", drag.id)] = true }, false, true)
    end
    S.restore(self.shot, drag.base, true)
    local seg = S.segmentById(self.shot, drag.id)
    if seg == nil then
        return
    end
    local t = self:snapTime(self:timeAtX(x), drag.targets)
    local start, finish = S.resizeSegment(self.shot, seg, drag.edge, t)
    if self.playheadAnywhere then
        self.playhead = drag.edge == "start" and start or finish
    end
    if self.topdown == nil then
        self:applyShotPose(self.playheadAnywhere and (drag.edge == "start" and start or finish - 1e-3) or self.playhead)
    end
    self:markDirty()
end

---------------------------------------------------------------------------------------------------
-- mazání

-- Smaže všechny vybrané věci (jízda vozidla se nemaže). Let bez posledního K-framu zmizí celý. S ripple se po smazaném
-- bloku zavře mezera: vše, co za ním následuje (bloky, body zájmu a body křivek kamery), se posune o jeho délku dřív;
-- bez ripple mezera zůstane a kamera v ní stojí.
function CinemaEditorScreen:deleteSelection(ripple)
    local shot = self.shot
    self:pushUndo()
    if self:selHasKind("part") then
        self:materializeParts()
    end
    local entries = self:selEntries()
    local removed = 0
    local gaps = {}
    local emptied = {}
    for _, e in ipairs(entries) do
        if e.kind == "key" then
            local track = e.owner.track
            for i, k in ipairs(track.keys) do
                if k == e.obj then
                    S.flightRemoveKey(shot, track, i)
                    removed = removed + 1
                    break
                end
            end
            if #track.keys == 0 then
                emptied[#emptied + 1] = e.owner
            end
        elseif e.kind == "block" then
            local _, index = S.segmentById(shot, e.obj.id)
            if index ~= nil and S.removeSegment(shot, index) then
                removed = removed + 1
                gaps[#gaps + 1] = { from = e.obj.t, to = S.segmentEnd(e.obj) }
            end
        elseif e.kind == "mark" then
            for mi, m in ipairs(e.owner.track.marks or {}) do
                if m == e.obj then
                    Mo.removeMark(e.owner.track, mi)
                    removed = removed + 1
                    break
                end
            end
        elseif e.kind == "action" then
            for ai, action in ipairs(e.owner.actions or {}) do
                if action == e.obj then
                    A.remove(e.owner, ai)
                    removed = removed + 1
                    break
                end
            end
        elseif e.kind == "focus" then
            for fi, f in ipairs(shot.focus) do
                if f == e.obj then
                    S.removeFocus(shot, fi)
                    removed = removed + 1
                    break
                end
            end
        end
    end
    for _, seg in ipairs(emptied) do
        local _, index = S.segmentById(shot, seg.id)
        if index ~= nil and S.removeSegment(shot, index) then
            gaps[#gaps + 1] = { from = seg.t, to = S.segmentEnd(seg) }
        end
    end
    if removed == 0 then
        table.remove(self.undoStack)
        self:showMessage(g_i18n:getText("cine_msg_nothingToDelete"))
        return
    end
    if ripple then
        table.sort(gaps, function(a, b) return a.from > b.from end)
        for _, gap in ipairs(gaps) do
            S.cutRange(shot, gap.from, gap.to)
            S.shiftAfter(shot, gap.to - S.KEY_SNAP, -(gap.to - gap.from))
        end
    end
    self:selClear()
    S.touch(shot)
    self:syncDrivers()
    self:markDirty()
    if self.topdown == nil then
        self:applyShotPose(self.playhead)
    end
end

---------------------------------------------------------------------------------------------------
-- blok: rozdělení a nahrazení režimu

-- Bloky, které jde rozdělit: Let (každý kus si vezme své K-framy) a režimy, jejichž pohyb nezávisí na průběhu bloku.
E.SPLITTABLE = { flight = true, follow = true, spotlight = true, static = true }

function CinemaEditorScreen:canSplit(seg, t)
    return E.SPLITTABLE[seg.track.mode] == true and t >= seg.t + S.MIN_SEGMENT and t <= S.segmentEnd(seg) - S.MIN_SEGMENT - S.MIN_GAP
end

-- Rozdělí blok seg na dvě části stejného druhu: první končí ve firstEnd, druhá začíná v secondStart a končí tam, kde končil
-- blok. K-framy se rozdělí podle času (ty v mezeře mezi částmi zaniknou), na řezu vznikne K-frame s pózou a zoomem, který
-- tam byl. Plynulé navázání zůstane první části. Vrací druhou část.
function CinemaEditorScreen:cutBlock(seg, firstEnd, secondStart)
    local shot = self.shot
    local d = seg.track.duration
    local d1 = firstEnd - seg.t
    local gap = secondStart - firstEnd
    local d2 = d - d1 - gap
    if S.hasKeys(seg.track) then
        local secondTrack = S.flightPiece(shot, seg.track, d1 + gap, d)
        secondTrack.smooth, secondTrack.blend = nil, nil
        seg.track = S.flightPiece(shot, seg.track, 0, d1)
        local second = { id = S.nextSegmentId(shot), t = secondStart, track = secondTrack }
        S.addSegment(shot, second)
        return second
    end
    local focalFirstEnd, focalSecondStart
    if not seg.track.autoZoom then
        focalFirstEnd, focalSecondStart = Mo.focalAt(seg.track, d1), Mo.focalAt(seg.track, d1 + gap)
    end
    local second = { id = S.nextSegmentId(shot), t = secondStart, track = copyOf(seg.track) }
    second.track.duration = d2
    second.track.smooth, second.track.blend = nil, nil
    -- zoom na řezu zůstane spojitý: ohnisko na kraji obou částí se vezme z původního průběhu (značka na řezu se tím stane krajem)
    if focalSecondStart ~= nil then
        second.track.focal = focalSecondStart
        seg.track.focal2 = focalFirstEnd
    end
    -- přechod úhlu sledování: první část skončí a druhá začne pod úhlem, který na řezu byl
    if seg.track.relAngle2 ~= nil then
        local rel, rel2 = seg.track.relAngle or 0, seg.track.relAngle2
        local function angleAt(at)
            return M.angleDiff(0, rel + M.angleDiff(rel, rel2) * Mo.progress(seg.track, at))
        end
        second.track.relAngle = angleAt(d1 + gap)
        seg.track.relAngle2 = angleAt(d1)
    end
    local first, rest = {}, {}
    for _, m in ipairs(seg.track.marks or {}) do
        local at = m.u * d
        if at < d1 then
            m.u = at / d1
            if m.u < 1 - 1e-6 then
                first[#first + 1] = m
            end
        else
            local c = copyOf(m)
            c.u = (at - d1 - gap) / d2
            if c.u > 1e-6 and c.u < 1 - 1e-6 then
                rest[#rest + 1] = c
            end
        end
    end
    seg.track.marks = #first > 0 and first or nil
    second.track.marks = #rest > 0 and rest or nil
    seg.track.duration = d1
    S.addSegment(shot, second)
    return second
end

-- Kusy bloku mezi jeho K-framy (a okraji): { id, seg, t0, t1 }. Jen blok, který jde rozdělit a má K-framy uvnitř;
-- jinak je jediným kusem blok sám, takže se nic nevrací.
function E.blockParts(seg)
    local track = seg.track
    if not E.SPLITTABLE[track.mode] then
        return {}
    end
    local d = track.duration or 0
    local inner = {}
    for _, obj in ipairs(track.keys or track.marks or {}) do
        local at = obj.t or obj.u * d
        if at > S.KEY_SNAP and at < d - S.KEY_SNAP then
            inner[#inner + 1] = { at = at, obj = obj }
        end
    end
    if #inner == 0 then
        return {}
    end
    local list, from, fromObj = {}, 0, nil
    local function add(to)
        list[#list + 1] = { id = string.format("%d:%s", seg.id, fromObj ~= nil and tostring(S.uid(fromObj)) or "s"), seg = seg,
            t0 = seg.t + from, t1 = seg.t + to }
    end
    for _, k in ipairs(inner) do
        add(k.at)
        from, fromObj = k.at, k.obj
    end
    add(d)
    return list
end

-- Vyjme úsek bloku [t0, t1] jako samostatný blok; zbytky vlevo a vpravo zůstanou, od něj o MIN_GAP. Příliš krátký zbytek
-- se k úseku přidá. Vrací blok s úsekem.
function CinemaEditorScreen:carveBlock(seg, t0, t1)
    t0, t1 = math.max(t0, seg.t), math.min(t1, S.segmentEnd(seg))
    if t0 - seg.t < S.MIN_GAP + S.MIN_SEGMENT then
        t0 = seg.t
    end
    if S.segmentEnd(seg) - t1 < S.MIN_GAP + S.MIN_SEGMENT then
        t1 = S.segmentEnd(seg)
    end
    local piece = seg
    if t0 > seg.t then
        piece = self:cutBlock(seg, t0 - S.MIN_GAP, t0)
    end
    if t1 < S.segmentEnd(piece) - S.KEY_SNAP then
        self:cutBlock(piece, t1, t1 + S.MIN_GAP)
    end
    return piece
end

-- Vybrané kusy bloků se vyjmou jako samostatné bloky (sousední kusy jednoho bloku splynou v jeden) a výběr je nahradí.
-- Vrací { [id kusu] = id bloku }.
function CinemaEditorScreen:materializeParts()
    local groups, order = {}, {}
    local sel = {}
    for _, e in ipairs(self:selEntries()) do
        if e.kind == "part" then
            local group = groups[e.owner.id]
            if group == nil then
                group = { seg = e.owner, items = {} }
                groups[e.owner.id] = group
                order[#order + 1] = group
            end
            group.items[#group.items + 1] = { t0 = e.obj.t0, t1 = e.obj.t1, id = e.id }
        else
            sel[#sel + 1] = { kind = e.kind, id = e.id }
        end
    end
    local mapping = {}
    for _, group in ipairs(order) do
        table.sort(group.items, function(a, b) return a.t0 < b.t0 end)
        local ranges = {}
        for _, item in ipairs(group.items) do
            local last = ranges[#ranges]
            if last ~= nil and item.t0 <= last.t1 + 1e-6 then
                last.t1 = math.max(last.t1, item.t1)
                last.ids[#last.ids + 1] = item.id
            else
                ranges[#ranges + 1] = { t0 = item.t0, t1 = item.t1, ids = { item.id } }
            end
        end
        for r = #ranges, 1, -1 do
            local range = ranges[r]
            local piece = self:carveBlock(group.seg, range.t0, range.t1)
            for _, id in ipairs(range.ids) do
                mapping[id] = piece.id
            end
            sel[#sel + 1] = { kind = "block", id = piece.id }
        end
    end
    self.sel = sel
    return mapping
end

-- Klik na blok: celý blok, nebo (blok s keyframy, který jde rozdělit) kus mezi dvěma keyframy. Klik na už vybraný celý blok
-- při puštění vybere kus pod kurzorem, klik na vybraný kus vybere zpět celý blok; táhne se vždy to, co je vybrané.
-- Vrací druh a věc, za kterou se táhne, a věc, která se puštěním bez tažení vybere samotná.
function CinemaEditorScreen:segmentClick(seg, t, toggle)
    local parts = E.blockParts(seg)
    local part, partSelected
    for _, p in ipairs(parts) do
        if t >= p.t0 and t <= p.t1 then
            part = p
        end
        if self:selHas("part", p) then
            partSelected = true
        end
    end
    if toggle then
        if part ~= nil and partSelected then
            self:selToggle("part", part)
            return "part", part, nil
        end
        self:selToggle("block", seg)
        return "block", seg, nil
    end
    local single = self:selCount() == 1
    if part ~= nil and single and self:selHas("block", seg) then
        return "block", seg, { kind = "part", obj = part }
    end
    if part ~= nil and partSelected then
        if self:selHas("part", part) then
            return "part", part, single and { kind = "block", obj = seg } or { kind = "part", obj = part }
        end
        self:selSet("part", part)
        return "part", part, nil
    end
    return "block", seg, self:clickSelect("block", seg, false)
end

-- Vložení do místa, kde leží blok, který jde rozdělit: rozdělí se v místě vložení, takže jeho zbytek odskočí za vložené bloky
-- (ostatní režimy se při vložení jen oříznou).
function CinemaEditorScreen:splitForInsert(segs, segIds)
    local lo = math.huge
    for _, seg in ipairs(segs) do
        lo = math.min(lo, seg.t)
    end
    local target
    for _, x in ipairs(self.shot.segments) do
        if not segIds[x.id] and E.SPLITTABLE[x.track.mode] and x.t < lo - S.KEY_SNAP and S.segmentEnd(x) > lo + S.KEY_SNAP
            and lo - S.MIN_GAP - x.t >= S.MIN_SEGMENT and S.segmentEnd(x) - lo >= S.MIN_SEGMENT then
            target = x
            break
        end
    end
    if target ~= nil then
        self:cutBlock(target, lo - S.MIN_GAP, lo)
    end
end

-- Rozdělí blok pod playheadem (nebo daný) na dva stejného režimu; značky se rozdělí podle času.
function CinemaEditorScreen:splitBlock(seg)
    local shot = self.shot
    seg = seg or S.segmentAt(shot, self.playhead)
    if seg == nil then
        self:showMessage(g_i18n:getText("cine_msg_noBlockAtPlayhead"))
        return
    end
    local t = self.playhead
    if not self:canSplit(seg, t) then
        self:showMessage(g_i18n:getText(E.SPLITTABLE[seg.track.mode] and "cine_msg_splitTooShort" or "cine_msg_splitNot"))
        return
    end
    self:pushUndo()
    local second = self:cutBlock(seg, t, t + S.MIN_GAP)
    self:setSelectedBlock(second)
    self:markDirty()
    self:showMessage(g_i18n:getText("cine_msg_split"))
end

-- Režim bloku se vymění za jiný; čas, délka, ohnisko, rozjezd, navázání a značky zůstanou, cíl se bere z původního režimu.
function CinemaEditorScreen:replaceBlockMode(seg, mode, side)
    local old = seg.track
    local track
    if mode == "static" then
        local cam = self:getFreeCamera()
        track = Mo.initStatic(cam.x, cam.y, cam.z, cam.yaw, cam.pitch)
    else
        local st = old.target ~= nil and self:targetState(old.target, self.playhead) or nil
        if st == nil then
            self:showMessage(g_i18n:getText("cine_msg_replaceNeedsTarget"))
            return
        end
        local cam = self:getFreeCamera()
        track = Mo.init(mode, old.target, cam.x, cam.y, cam.z, st.x, st.y, st.z, st.heading, side)
    end
    track.duration, track.focal = old.duration, old.focal
    track.marks = old.marks
    track.easeIn, track.easeOut = old.easeIn, old.easeOut
    track.smooth, track.blend = old.smooth, old.blend
    S.standToKeys(track)
    self:pushUndo()
    seg.track = track
    S.touch(self.shot)
    self:markDirty()
    self:applyShotPose(self.playhead)
    self:showMessage(string.format(g_i18n:getText("cine_msg_replaced"), E.trackLabel(track)))
end

function CinemaEditorScreen:toggleSnap()
    self.snapOn = self.snapOn == false
    self:showMessage(g_i18n:getText(self.snapOn and "cine_msg_snapOn" or "cine_msg_snapOff"))
end

function CinemaEditorScreen:toggleEditMode()
    self.editMode = self.editMode == "insert" and "overwrite" or "insert"
    self:showMessage(g_i18n:getText("cine_msg_editMode_" .. self.editMode))
end

---------------------------------------------------------------------------------------------------
-- kopírovat a vložit (schránka platí i mezi záběry)

-- Zkopíruje vybrané bloky (i s K-framy), kusy bloků, body zájmu a akce do schránky (časy relativně k nejdřívější věci).
function CinemaEditorScreen:copySelection()
    local items, first = {}, math.huge
    for _, e in ipairs(self:selEntries()) do
        local t0 = self:clipTimes(e)
        local item
        if e.kind == "block" then
            item = { kind = "block", data = copyOf(e.obj.track) }
        elseif e.kind == "part" then
            item = { kind = "block", data = self:pieceOf(e.owner.track, e.obj.t0 - e.owner.t, e.obj.t1 - e.owner.t) }
        elseif e.kind == "focus" then
            item = { kind = "focus", data = copyOf(e.obj) }
        elseif e.kind == "action" then
            item = { kind = "action", data = copyOf(e.obj), actorIndex = e.ownerIndex }
        end
        if item ~= nil then
            item.t0 = t0
            items[#items + 1] = item
            first = math.min(first, t0)
        end
    end
    if #items == 0 then
        self:showMessage(g_i18n:getText("cine_msg_nothingToCopy"))
        return
    end
    E.clipboard = { items = items, base = first }
    self:showMessage(string.format(g_i18n:getText("cine_msg_copied"), #items))
end

-- Vloží schránku od playheadu: bloky se překryjí nebo vloží podle režimu úprav, akce jdou do vybraného vozidla
-- (jinak do vozidla, ze kterého se kopírovalo).
function CinemaEditorScreen:pasteClipboard()
    local clip = E.clipboard
    if clip == nil then
        self:showMessage(g_i18n:getText("cine_msg_clipboardEmpty"))
        return
    end
    local shot = self.shot
    self:pushUndo()
    local segs, segIds, focusSet, copies = {}, {}, {}, {}
    local pasted = 0
    for _, item in ipairs(clip.items) do
        local t = self.playhead + (item.t0 - clip.base)
        if item.kind == "block" then
            local seg = { id = S.nextSegmentId(shot), t = t, track = copyOf(item.data) }
            S.addSegment(shot, seg)
            segs[#segs + 1] = seg
            segIds[seg.id] = true
            copies[#copies + 1] = { kind = "block", id = seg.id }
            pasted = pasted + 1
        elseif item.kind == "focus" then
            local index = S.setFocus(shot, t, item.data.target, item.data.height)
            shot.focus[index].blend = item.data.blend
            focusSet[shot.focus[index]] = true
            copies[#copies + 1] = { kind = "focus", id = S.uid(shot.focus[index]) }
            pasted = pasted + 1
        elseif item.kind == "action" then
            local actor = shot.actors[self.activeTarget > 0 and self.activeTarget or item.actorIndex]
            -- akce postavy jdou jen postavě a akce vozidla jen vozidlu; kopie výstupu je nový výstup (nová část trasy)
            if actor ~= nil and A.isPersonKind(item.data.kind) == CinemaPerson.isPerson(actor) then
                local c = copyOf(item.data)
                c.t = math.max(A.minTime(actor), t - (actor.delay or 0))
                c.leg = nil
                A.add(actor, c)
                copies[#copies + 1] = { kind = "action", id = S.uid(c) }
                pasted = pasted + 1
            end
        end
    end
    if pasted == 0 then
        table.remove(self.undoStack)
        self:showMessage(g_i18n:getText("cine_msg_nothingToPaste"))
        return
    end
    if #segs > 0 then
        if self.editMode == "insert" then
            self:splitForInsert(segs, segIds)
            openGap(shot, segs, { segs = segIds, focus = focusSet })
        end
        for _, seg in ipairs(segs) do
            self:clearSpanForNewBlock(seg, segIds)
        end
        S.sortSegments(shot)
    end
    self.sel = copies
    S.touch(shot)
    self.actorRt = {}
    self:markDirty()
    self:showMessage(string.format(g_i18n:getText("cine_msg_pasted"), pasted))
end
