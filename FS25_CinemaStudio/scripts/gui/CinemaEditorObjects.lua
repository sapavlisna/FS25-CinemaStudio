-- Objekty ve světě na ose: skupina řádků „Objekty“ (sbalitelná, přetahuje se za název jako ostatní řádky), v ní řádek
-- každého objektu (brána, budova se světly nebo výrobou, stroj) se značkami akcí. Objekt se vybírá přes T, akce se
-- přidávají pravým tlačítkem na řádku k ukazateli, značky se táhnou v čase. Při přehrávání je provádí CinemaActions
-- a po něm vrátí stav.

local E = CinemaEditorScreen
local S = CinemaShot
local A = CinemaActions
local O = CinemaObjects
local W = CinemaWorld

local function t(key)
    return g_i18n:getText(key)
end

function CinemaEditorScreen:objects()
    self.shot.objects = self.shot.objects or {}
    return self.shot.objects
end

-- Skupina objektů je na ose, když nějaké jsou, nebo když si ji uživatel přidal.
function CinemaEditorScreen:hasObjectsRow()
    return #self:objects() > 0 or self.shot.objectsRow == true
end

function CinemaEditorScreen:objectsCollapsed()
    return self.shot.objectsCollapsed == true or self:isCompact()
end

function CinemaEditorScreen:getObjectsGroupH()
    return E.ROW_H * (1 + (self:objectsCollapsed() and 0 or #self:objects()))
end

-- Spodek záhlaví skupiny a řádku objektu k (pod záhlavím, první nejvýš); nil, když skupina není vidět.
function CinemaEditorScreen:getObjectsHeaderY()
    local row = self:rowLayout().byKey.objects
    return row ~= nil and row.y + row.h - E.ROW_H or nil
end

function CinemaEditorScreen:getObjectRowY(k)
    local hy = self:getObjectsHeaderY()
    return hy ~= nil and hy - k * E.ROW_H or nil
end

-- Značka akce objektu k pod kurzorem: index akce, nebo nil.
function CinemaEditorScreen:objectActionAt(k, x)
    local obj = self:objects()[k]
    local hit = E.ACTION_HIT_PX * g_pixelSizeScaledX
    local best, bestScore = nil, math.huge
    for j, action in ipairs(obj ~= nil and obj.actions or {}) do
        local x0, x1 = self:xAtTime(action.t), self:xAtTime(A.endTime(action))
        local score = nil
        if math.abs(x - x0) <= hit then
            score = math.abs(x - x0)
        elseif x > x0 and x <= x1 then
            score = hit + (x - x0)
        end
        if score ~= nil and score < bestScore then
            best, bestScore = j, score
        end
    end
    return best
end

-- Zásah ve skupině: { kind = "objectsCollapse" | "objectsHeader" | "object" | "objAction", index, action, rowKey }, nebo nil.
function CinemaEditorScreen:hitObjects(x, y)
    local hy = self:getObjectsHeaderY()
    if hy == nil then
        return nil
    end
    if y >= hy and y <= hy + E.ROW_H then
        if x >= E.ARROW_X0 and x < E.ARROW_X1 then
            return { kind = "objectsCollapse" }
        end
        return { kind = "objectsHeader", rowKey = x >= E.LABEL_X and x < E.TRACK_X0 and "objects" or nil }
    end
    if self:objectsCollapsed() then
        return nil
    end
    for k in ipairs(self:objects()) do
        local ry = self:getObjectRowY(k)
        if y >= ry and y < ry + E.ROW_H then
            local j = x >= E.TRACK_X0 and self:objectActionAt(k, x) or nil
            if j ~= nil then
                return { kind = "objAction", index = k, action = j }
            end
            return { kind = "object", index = k }
        end
    end
    return nil
end

function CinemaEditorScreen:toggleObjects()
    self.shot.objectsCollapsed = not self.shot.objectsCollapsed or nil
    self:markDirty()
end

function CinemaEditorScreen:drawObjectsGroup()
    local hy = self:getObjectsHeaderY()
    if hy == nil then
        return
    end
    local gfx, ui = E.gfx, E.UI
    local px = g_pixelSizeScaledX
    local list = self:objects()
    self:drawRowBase(hy, E.ROW_H, false, string.format(t("cine_objects_label"), #list), nil)
    gfx.text(E.ARROW_X0 + 0.002, hy + E.ROW_H * 0.5 - E.TEXT_SIZE * 0.3, E.TEXT_SIZE * 0.75, self:objectsCollapsed() and ">" or "v",
        #list > 0 and ui.text or ui.dim, RenderText.ALIGN_LEFT, true)
    gfx.text(E.TRACK_X0 + 0.006, hy + E.ROW_H * 0.5 - E.TEXT_SIZE * 0.28, E.TEXT_SIZE * 0.68,
        t(#list > 0 and "cine_objects_hint" or "cine_objects_empty"), ui.dim, RenderText.ALIGN_LEFT)
    if self:objectsCollapsed() then
        return
    end
    for k, obj in ipairs(list) do
        local ry = self:getObjectRowY(k)
        local exists = O.exists(obj)
        self:drawRowBase(ry, E.ROW_H, self.activeObject == k, "  " .. (obj.name or "?"), nil)
        local cy = ry + E.ROW_H * 0.5
        gfx.clipTrack()
        if #obj.actions == 0 then
            gfx.text(E.TRACK_X0 + 0.006, cy - E.TEXT_SIZE * 0.28, E.TEXT_SIZE * 0.68,
                t(exists and "cine_object_noActions" or "cine_object_missing"), exists and ui.dim or ui.cut, RenderText.ALIGN_LEFT)
        end
        for j, action in ipairs(obj.actions) do
            local selected = self.selObjAction == action
            local c = A.color(action)
            local x0, x1 = self:xAtTime(action.t), self:xAtTime(A.endTime(action))
            if x1 > x0 then
                gfx.rect(x0, ry + E.ROW_H * 0.3, x1 - x0, E.ROW_H * 0.4, { c[1], c[2], c[3], selected and 0.9 or 0.6 })
            end
            local isOff = (action.value or 1) == 0
            gfx.keyMarker(x0, cy, selected and E.KEY_PX + 1 or E.KEY_PX - 1,
                selected and ui.keySelected or (isOff and { c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, 1 } or { c[1], c[2], c[3], 1 }))
            local nextAction = obj.actions[j + 1]
            local nextX = nextAction ~= nil and self:xAtTime(nextAction.t) or math.huge
            local label = A.label(action)
            local size = E.TEXT_SIZE * 0.66
            local lx = x0 + 8 * px
            local width = getTextWidth(size, label)
            if selected or lx + width + 4 * px < nextX then
                gfx.rect(lx - 2 * px, cy - size * 0.55, width + 4 * px, size * 1.3, { 0, 0, 0, 0.6 })
                gfx.text(lx, cy - size * 0.35, size, label, exists and ui.text or ui.cut, RenderText.ALIGN_LEFT, selected)
            end
        end
        gfx.setClip(nil)
    end
end

---------------------------------------------------------------------------------------------------
-- přidání: výběr ve scéně (T)

function CinemaEditorScreen:pickObject()
    self.pendingAction = { object = true }
    self.picking = true
    self:needCursor()
    self:showMessage(t("cine_msg_pickObject"))
end

function CinemaEditorScreen:addObject(obj)
    for k, other in ipairs(self:objects()) do
        if O.same(other, obj) then
            self.activeObject = k
            self.shot.objectsCollapsed = nil
            self:showMessage(t("cine_msg_objectAlready"))
            return k
        end
    end
    self:pushUndo()
    local list = self:objects()
    local id = 0
    for _, other in ipairs(list) do
        id = math.max(id, other.id or 0)
    end
    obj.id = id + 1
    list[#list + 1] = obj
    self.activeObject = #list
    self.shot.objectsCollapsed = nil
    S.touch(self.shot)
    self:markDirty()
    self:showMessage(string.format(t("cine_msg_objectAdded"), obj.name or "?"))
    return #list
end

-- Brána nebo budova pod kurzorem (výběr T); nil, když tam žádná není.
function CinemaEditorScreen:worldObjectAt(x, y)
    return O.candidateAt(O.candidates(self.cam, x, y))
end

-- Klik ve scéně při výběru objektu nebo bez úkolu (T): brána nebo budova. true, když se klik spotřeboval.
function CinemaEditorScreen:pickObjectAt(x, y, pending)
    local c = self:worldObjectAt(x, y)
    if c == nil then
        return false
    end
    self.picking = false
    self.pendingAction = nil
    if pending ~= nil and pending.object then
        self:addObject(O.fromCandidate(c))
    else
        self:openWorldObjectMenu(c, x, y)
    end
    return true
end

-- Značky bran a budov při výběru T.
function CinemaEditorScreen:drawObjectPick()
    local list = O.candidates(self.cam, self.mouseX, self.mouseY)
    local hover = O.candidateAt(list)
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    for _, c in ipairs(list) do
        local isHover = c == hover
        local r = isHover and 12 or 6
        local color = isHover and E.UI.pickHover or E.UI.pickBox
        E.gfx.outline(c.sx - r * px, c.sy - r * py, c.sx + r * px, c.sy + r * py, isHover and 3 or 1.5, color)
        E.gfx.line(c.sx - r * px, c.sy, c.sx + r * px, c.sy, 1, color)
        if isHover then
            E.gfx.text(c.sx, c.sy + r * py + 0.006, E.TEXT_SIZE, O.candidateName(c), E.UI.pickHover, RenderText.ALIGN_CENTER, true)
        end
    end
end

---------------------------------------------------------------------------------------------------
-- akce

function CinemaEditorScreen:addObjectAction(k, action)
    local obj = self:objects()[k]
    if obj == nil then
        return
    end
    self:pushUndo()
    A.add(obj, action)
    self.activeObject, self.selObjAction, self.objectFocus = k, action, true
    S.touch(self.shot)
    self:markDirty()
    self:showMessage(string.format(t("cine_msg_objectAction"), A.label(action), action.t))
end

local function item(text, action, opts)
    local entry = { text = text, action = action }
    for key, v in pairs(opts or {}) do
        entry[key] = v
    end
    return entry
end

-- Položky „akce objektu k v čase at“: u bran otevřít / zavřít, u budov světla a výroba po skupinách, u stroje akce vozidla
-- (světla v podmenu).
function CinemaEditorScreen:objectActionItems(k, at, x, y, onlyLights)
    local obj = self:objects()[k]
    local actor = O.actor(obj)
    local items, lights = {}, false
    for _, kind in ipairs(A.ORDER) do
        local def = A.KINDS[kind]
        local values = def.payload and {} or A.availableValues(actor, 0, kind)
        if #values > 0 and def.light and not onlyLights then
            lights = true
        elseif #values > 0 and (def.light == true) == (onlyLights == true) then
            local subs = def.sub and O.subs(obj, kind) or { {} }
            for _, sub in ipairs(subs) do
                for _, value in ipairs(values) do
                    local label = t(string.format("cine_act_%s_%d", kind, value))
                    local subLabel, link = sub.label, nil
                    if kind == "hose" and value == 1 then
                        -- zapojení se bere z toho, jak je hadice ve hře zapojená teď
                        link = O.readHose(O.target(obj), sub.sub)
                        if link ~= nil then
                            local source = link.source ~= nil and W.find(link.source) or nil
                            subLabel = string.format("%s → %s", sub.label, link.pond and t("cine_hose_pond") or W.name(source))
                        end
                    end
                    if subLabel ~= nil then
                        label = string.format("%s: %s", label, subLabel)
                    end
                    local needsLink = kind == "hose" and value == 1 and link == nil
                    if needsLink then
                        label = string.format("%s (%s)", label, t("cine_hose_connectFirst"))
                    end
                    items[#items + 1] = item(label, function(s)
                        s:addObjectAction(k, { t = at, kind = kind, value = value, entry = 0, sub = sub.sub, subLabel = subLabel, link = link })
                    end, { disabled = needsLink })
                end
            end
        end
    end
    if lights then
        table.insert(items, 1, item(t("cine_act_group_lights"), function(s)
            s:openMenu(t("cine_act_group_lights"), s:objectActionItems(k, at, x, y, true), x, y)
        end, { submenu = true }))
    end
    if #items == 0 then
        items[1] = item(t(O.exists(obj) and "cine_act_none" or "cine_object_missing"), function() end, { disabled = true })
    end
    return items
end

function CinemaEditorScreen:openObjectActionMenu(k, x, y)
    local at = self.playhead
    self:openMenu(string.format(t("cine_menu_actionAtTitle"), at), self:objectActionItems(k, at, x, y), x, y)
end

function CinemaEditorScreen:openObjectsMenu(x, y)
    local items = {
        item(t("cine_objects_pick"), function(s) s:pickObject() end),
        item(t(self:objectsCollapsed() and "cine_props_expand" or "cine_props_collapse"), function(s) s:toggleObjects() end,
            { disabled = #self:objects() == 0 }),
        item(t("cine_props_hide"), function(s)
            s:pushUndo()
            s.shot.objectsRow = nil
            s:markDirty()
        end, { disabled = #self:objects() > 0 }),
    }
    self:openMenu(t("cine_objects_title"), items, x, y)
end

function CinemaEditorScreen:openObjectRowMenu(k, x, y)
    local obj = self:objects()[k]
    if obj == nil then
        return
    end
    self.activeObject, self.objectFocus = k, true
    local items = {
        item(string.format(t("cine_object_actionHere"), self.playhead), function(s) s:openObjectActionMenu(k, x, y) end, { submenu = true }),
        item(t("cine_object_lookAt"), function(s)
            local ox, oy, oz = O.position(obj)
            if ox ~= nil then
                s:lookAtPoint(ox, oy, oz)
            end
        end, { disabled = not O.exists(obj) }),
        item(t("cine_menu_fill"), function(s)
            local v = obj.type == "vehicle" and W.find(obj.uid) or nil
            if v ~= nil then
                s:openFillMenu(obj.name or "?", { v }, nil, x, y)
            end
        end, { submenu = true, disabled = obj.type ~= "vehicle" or W.find(obj.uid) == nil }),
        { text = "", separator = true, disabled = true },
        item(t("cine_object_delete"), function(s)
            s:pushUndo()
            table.remove(s:objects(), k)
            s.activeObject, s.selObjAction = nil, nil
            S.touch(s.shot)
            s:markDirty()
        end),
    }
    self:openMenu(obj.name or "?", items, x, y)
end

-- Menu značky akce objektu: posun v čase, délka, k ukazateli, smazání.
function CinemaEditorScreen:openObjActionMenu(k, j, x, y)
    local obj = self:objects()[k]
    local action = obj ~= nil and obj.actions[j] or nil
    if action == nil then
        return
    end
    self.activeObject, self.selObjAction, self.objectFocus = k, action, true
    local function edit(s, fn)
        s:pushUndo()
        fn()
        S.touch(s.shot)
        s:markDirty()
    end
    local function moveTo(s, time)
        edit(s, function()
            for index, other in ipairs(obj.actions) do
                if other == action then
                    A.move(obj, index, time)
                    break
                end
            end
        end)
    end
    local items = {
        E.stepItem(function() return string.format(t("cine_menu_actionLater"), action.t, 0.5) end,
            function(s) moveTo(s, action.t + 0.5) end, function(s) moveTo(s, action.t - 0.5) end),
        item(string.format(t("cine_object_toPlayhead"), self.playhead), function(s) moveTo(s, s.playhead) end),
        E.stepItem(function() return string.format(t("cine_menu_actionLonger"), A.endTime(action) - action.t) end,
            function(s) edit(s, function() A.setDuration(action, A.endTime(action) - action.t + 0.5) end) end,
            function(s)
                if action.dur == nil then
                    return
                end
                edit(s, function()
                    local shorter = A.endTime(action) - action.t - 0.5
                    A.setDuration(action, shorter >= A.MIN_DURATION and shorter or nil)
                end)
            end, { disabled = not A.canStretch(action) }),
        { text = "", separator = true, disabled = true },
        item(t("cine_menu_actionDelete"), function(s)
            edit(s, function()
                for index, other in ipairs(obj.actions) do
                    if other == action then
                        A.remove(obj, index)
                        break
                    end
                end
            end)
            s.selObjAction = nil
        end),
    }
    self:openMenu(string.format(t("cine_menu_actionEditTitle"), A.label(action)), items, x, y)
end

-- Menu brány nebo budovy vybrané přes T: přidat na osu (a rovnou akci k ukazateli).
function CinemaEditorScreen:openWorldObjectMenu(c, x, y)
    local name = O.candidateName(c)
    local items = {
        item(t("cine_object_add"), function(s) s:addObject(O.fromCandidate(c)) end),
        item(string.format(t("cine_object_addAction"), self.playhead), function(s)
            local k = s:addObject(O.fromCandidate(c))
            if k ~= nil then
                s:openObjectActionMenu(k, x, y)
            end
        end, { submenu = true }),
    }
    self:openMenu(name, items, x, y)
end

-- Volná kamera se natočí na bod (zůstane, kde je).
function CinemaEditorScreen:lookAtPoint(x, y, z)
    local cam = self.cam
    local yaw, pitch = CinemaMath.yawPitchFromDirection(x - cam.x, y - cam.y, z - cam.z)
    self.vel = { 0, 0, 0 }
    CinemaCamera.setPose(cam, cam.x, cam.y, cam.z, CinemaMath.quatFromYawPitchRoll(yaw, pitch, 0), self.targetFocal)
end

---------------------------------------------------------------------------------------------------
-- tažení značky v čase

function CinemaEditorScreen:beginObjectActionDrag(k, j, x)
    local obj = self:objects()[k]
    local action = obj ~= nil and obj.actions[j] or nil
    if action == nil then
        return
    end
    self.activeObject, self.selObjAction, self.objectFocus = k, action, true
    self.drag = { kind = "objAction", object = k, action = action, dx = self:timeAtX(x) - action.t }
end

function CinemaEditorScreen:dragObjectAction(x)
    local drag = self.drag
    local obj = self:objects()[drag.object]
    if obj == nil then
        return
    end
    local time = math.max(0, self:timeAtX(x) - drag.dx)
    if not E.isShift() then
        time = math.floor(time * 10 + 0.5) / 10
    end
    if math.abs(time - drag.action.t) < 1e-6 then
        return
    end
    if not drag.moved then
        self:pushUndo()
        drag.moved = true
    end
    for index, other in ipairs(obj.actions) do
        if other == drag.action then
            A.move(obj, index, time)
            break
        end
    end
    S.touch(self.shot)
    self:markDirty()
end

---------------------------------------------------------------------------------------------------
-- přehrávání: akce objektů běží jako akce herců (čas od začátku záběru), po přehrávání se stav vrátí

function CinemaEditorScreen:prepareObjects(t0)
    self.objectRt = {}
    for k, obj in ipairs(self:objects()) do
        local rt, actor = {}, O.actor(obj)
        A.prepare(rt, actor, t0)
        self.objectRt[k] = { rt = rt, actor = actor }
    end
end

function CinemaEditorScreen:updateObjects(dt, time)
    for _, entry in pairs(self.objectRt or {}) do
        A.update(entry.rt, entry.actor, time, dt)
    end
end

function CinemaEditorScreen:stopObjects()
    for _, entry in pairs(self.objectRt or {}) do
        A.finish(entry.rt)
    end
    self.objectRt = nil
end

-- Stav objektů v čase t (po R / B); přehrávání nebo další náhled ho vrátí.
function CinemaEditorScreen:showObjectStates(time)
    self:clearObjectStates()
    self.objectState = {}
    for k, obj in ipairs(self:objects()) do
        local rt, actor = {}, O.actor(obj)
        A.prepare(rt, actor, time)
        rt.act.preview = true
        A.update(rt, actor, time, 0)
        self.objectState[k] = rt
    end
end

function CinemaEditorScreen:clearObjectStates()
    for _, rt in pairs(self.objectState or {}) do
        A.finish(rt)
    end
    self.objectState = nil
end
