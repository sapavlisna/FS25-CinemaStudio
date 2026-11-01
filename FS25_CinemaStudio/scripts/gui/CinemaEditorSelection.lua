-- Výběr na časové ose: jediný seznam vybraných věcí. Věc se pozná podle druhu a stálého čísla (S.uid, u bloku jeho id),
-- takže výběr přežije krok zpět. Druhy: block (blok kamery), part (kus bloku mezi dvěma jeho K-framy), key (K-frame Letu),
-- mark (K-frame uvnitř režimu), focus (bod zájmu), action (akce vozidla), drive (jízda vozidla), span / wait (úsek trasy
-- a pauza v bodě = bod trasy), stop (stání z křivky rychlosti = jeho konec v křivce).
-- Poslední vybraná věc je hlavní: podle ní se řídí klávesy (výš / níž), stavový řádek a nabídka.

local E = CinemaEditorScreen
local S = CinemaShot

local function idOf(kind, obj)
    if kind == "block" or kind == "part" then
        return obj.id
    end
    return S.uid(obj)
end

-- Každá funkce vrací věc, její index v seznamu, vlastníka a index vlastníka (u K-framu a značky blok, u akce vozidlo).
local RESOLVE = {
    key = function(shot, id)
        for si, seg in ipairs(shot.segments) do
            for i, k in ipairs(seg.track.keys or {}) do
                if k.uid == id then
                    return k, i, seg, si
                end
            end
        end
    end,
    block = function(shot, id)
        local seg, i = S.segmentById(shot, id)
        return seg, i
    end,
    part = function(shot, id)
        local segId = tostring(id):match("^(%d+):")
        local seg, si = S.segmentById(shot, tonumber(segId))
        if seg == nil then
            return nil
        end
        for i, p in ipairs(E.blockParts(seg)) do
            if p.id == id then
                return p, i, seg, si
            end
        end
    end,
    mark = function(shot, id)
        for si, seg in ipairs(shot.segments) do
            for mi, m in ipairs(seg.track.marks or {}) do
                if m.uid == id then
                    return m, mi, seg, si
                end
            end
        end
    end,
    focus = function(shot, id)
        for i, f in ipairs(shot.focus) do
            if f.uid == id then
                return f, i
            end
        end
    end,
    action = function(shot, id)
        for ai, a in ipairs(shot.actors) do
            for j, action in ipairs(a.actions or {}) do
                if action.uid == id then
                    return action, j, a, ai
                end
            end
        end
    end,
    drive = function(shot, id)
        for ai, a in ipairs(shot.actors) do
            if a.uid == id then
                return a, ai
            end
        end
    end,
}
local function routePoint(shot, id)
    for ai, a in ipairs(shot.actors) do
        for j, p in ipairs(a.points or {}) do
            if p.uid == id then
                return p, j, a, ai
            end
        end
    end
end
RESOLVE.span = routePoint
RESOLVE.wait = routePoint
RESOLVE.stop = function(shot, id)
    for ai, a in ipairs(shot.actors) do
        local curve = a.curves ~= nil and a.curves.speed or nil
        for k, p in ipairs(curve ~= nil and curve.points or {}) do
            if p.uid == id then
                return p, k, a, ai
            end
        end
    end
end
function CinemaEditorScreen:selClear()
    self.sel = {}
end

-- Věci ze seznamu { kind, id }, které v záběru ještě existují: { kind, id, obj, index, owner, ownerIndex }.
function CinemaEditorScreen:selResolve(items)
    local list = {}
    for _, entry in ipairs(items) do
        local obj, index, owner, ownerIndex = RESOLVE[entry.kind](self.shot, entry.id)
        if obj ~= nil then
            list[#list + 1] = { kind = entry.kind, id = entry.id, obj = obj, index = index, owner = owner, ownerIndex = ownerIndex }
        end
    end
    return list
end

-- Vybrané věci, které ještě existují (zaniklé se z výběru vyřadí).
function CinemaEditorScreen:selEntries()
    local list = self:selResolve(self.sel or {})
    local alive = {}
    for i, e in ipairs(list) do
        alive[i] = { kind = e.kind, id = e.id }
    end
    self.sel = alive
    return list
end

-- Klíč věci pro množiny „kromě těchto“ (přichytávání, přepsání).
function E.itemKey(kind, id)
    return kind .. ":" .. tostring(id)
end

function CinemaEditorScreen:selIdOf(kind, obj)
    return idOf(kind, obj)
end

function CinemaEditorScreen:selHasKind(kind)
    for _, entry in ipairs(self.sel or {}) do
        if entry.kind == kind then
            return true
        end
    end
    return false
end

function CinemaEditorScreen:selCount()
    return #self:selEntries()
end

function CinemaEditorScreen:selHas(kind, obj)
    if obj == nil then
        return false
    end
    local id = idOf(kind, obj)
    for _, entry in ipairs(self.sel or {}) do
        if entry.kind == kind and entry.id == id then
            return true
        end
    end
    return false
end

-- Hlavní (poslední vybraná) věc daného druhu: obj, index, owner, ownerIndex.
function CinemaEditorScreen:selPrimary(kind)
    local found
    for _, e in ipairs(self:selEntries()) do
        if e.kind == kind then
            found = e
        end
    end
    if found == nil then
        return nil
    end
    return found.obj, found.index, found.owner, found.ownerIndex
end

function CinemaEditorScreen:selSet(kind, obj)
    self.sel = obj ~= nil and { { kind = kind, id = idOf(kind, obj) } } or {}
end

function CinemaEditorScreen:selAdd(kind, obj)
    if obj ~= nil and not self:selHas(kind, obj) then
        self.sel[#self.sel + 1] = { kind = kind, id = idOf(kind, obj) }
    end
end

function CinemaEditorScreen:selRemove(kind, obj)
    local id = idOf(kind, obj)
    for i = #self.sel, 1, -1 do
        if self.sel[i].kind == kind and self.sel[i].id == id then
            table.remove(self.sel, i)
        end
    end
end

-- Shift + klik: věc se přidá, nebo (je-li vybraná) ubere.
function CinemaEditorScreen:selToggle(kind, obj)
    if self:selHas(kind, obj) then
        self:selRemove(kind, obj)
    else
        self:selAdd(kind, obj)
    end
end

-- Zkratky pro jednotlivé druhy; jednoduché nastavení výběr nahradí.
-- Hlavní vybraný K-frame Letu: blok, index K-framu, K-frame.
function CinemaEditorScreen:selectedKey()
    local key, index, seg = self:selPrimary("key")
    return seg, index, key
end

function CinemaEditorScreen:setSelectedKey(seg, index)
    self:selSet("key", seg ~= nil and seg.track.keys[index] or nil)
end

-- Hlavní vybraná značka v režimu: úsek, index značky, značka.
function CinemaEditorScreen:selectedMark()
    local mark, index, seg = self:selPrimary("mark")
    return seg, index, mark
end

function CinemaEditorScreen:setSelectedMark(seg, index)
    self:selSet("mark", seg.track.marks[index])
end

-- Hlavní vybraná akce vozidla: číslo vozidla a index akce.
function CinemaEditorScreen:selectedAction()
    local _, index, _, actorIndex = self:selPrimary("action")
    return actorIndex, index
end

function CinemaEditorScreen:setSelectedAction(actorIndex, index)
    local actor = self.shot.actors[actorIndex]
    self:selSet("action", actor ~= nil and actor.actions[index] or nil)
end

function CinemaEditorScreen:selectedFocus()
    local _, index = self:selPrimary("focus")
    return index
end

function CinemaEditorScreen:setSelectedFocus(index)
    self:selSet("focus", index ~= nil and self.shot.focus[index] or nil)
end

function CinemaEditorScreen:setSelectedBlock(seg)
    self:selSet("block", seg)
end
