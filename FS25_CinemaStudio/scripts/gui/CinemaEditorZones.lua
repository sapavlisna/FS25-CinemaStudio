-- Zóny na poli v editoru: co je sklizeno a co ne. Z menu pole (Zóny sklizně…): sklizeno podle kurzu Courseplay až do bodu,
-- na který klikneš, nebo až do polohy kombajnu, a obdélníky „sklizeno“ / „nesklizeno“ ze tří kliknutí (kliká se ve scéně,
-- i v pohledu shora). Zóny se kreslí na poli, dokud je pole vybrané; reset je přepíše do hry po nastavení celého pole.

local E = CinemaEditorScreen
local W = CinemaWorld
local Pr = CinemaProps
local Z = CinemaZones
local Cam = CinemaCamera

E.ZONE_CP_COLOR = { 0.55, 0.85, 0.45, 1 }
E.ZONE_FAR_MIN = 20 -- m; klik dál od kurzu hlásí chybu (nejméně, jinak dvojnásobek pracovní šířky)
E.ZONE_LEAD = 8 -- m; o kolik je sklizeno před středem stroje (žací stůl)
E.ZONE_LEAD_MAX = 30
E.ZONE_EXTRA_STEP = 0.5 -- m; změna šířky pruhu kurzu
E.ZONE_EXTRA_MAX = 6

local function t(key)
    return g_i18n:getText(key)
end

-- Je bod v poli? Do tolerance (m) za hranicí se bere jako v poli: řádek kurzu končí na hranici a roh pruhu leží těsně vedle.
local function insideField(p, tolerance)
    local field = Pr.findField(p.field)
    local points = field ~= nil and Pr.fieldPolygon(field) or {}
    tolerance = tolerance or 0
    return function(x, z)
        if #points < 3 then
            return false
        end
        if Pr.insidePolygon(points, x, z) then
            return true
        end
        for i = 1, #points do
            local a, b = points[i], points[i % #points + 1]
            local dx, dz = b[1] - a[1], b[2] - a[2]
            local len2 = dx * dx + dz * dz
            local t = len2 > 1e-9 and math.max(0, math.min(1, ((x - a[1]) * dx + (z - a[2]) * dz) / len2)) or 0
            if math.sqrt((x - a[1] - dx * t) ^ 2 + (z - a[2] - dz * t) ^ 2) <= tolerance then
                return true
            end
        end
        return false
    end
end

E.ZONE_EDGE_TOLERANCE = 1.5 -- m

local function courseKey(vehicle)
    return "course:" .. tostring(W.uid(vehicle)):gsub("[^%w_%-]", "_")
end

---------------------------------------------------------------------------------------------------
-- zápis do pole

-- Přidá zóny k poli p; zóna podle kurzu stejného stroje nahradí dřívější. false, když by bylo kvádrů příliš.
function CinemaEditorScreen:addZones(p, added)
    local kept = {}
    for _, zone in ipairs(Z.decode(p.zones)) do
        local replaced = false
        for _, n in ipairs(added) do
            replaced = replaced or (zone.src:sub(1, 7) == "course:" and zone.src == n.src)
        end
        if not replaced then
            kept[#kept + 1] = zone
        end
    end
    for _, n in ipairs(added) do
        kept[#kept + 1] = n
    end
    local _, _, quads = Z.summary(kept)
    if quads > Z.MAX_QUADS then
        self:showMessage(string.format(t("cine_msg_zoneMax"), Z.MAX_QUADS))
        return false
    end
    self:pushUndo()
    p.zones = Z.encode(kept)
    self:refreshZoneWindrows(p)
    self:markDirty()
    return true
end

-- Řádky slámy mají být jen tam, kde kombajn jel: po změně zón se vezmou z jejich sklizených částí.
function CinemaEditorScreen:refreshZoneWindrows(p)
    if p.windrow == nil then
        return
    end
    local lines = Z.cutLines(Z.decode(p.zones))
    if #lines > 0 then
        p.windrowLines, p.windrowSource = Pr.encodeLines(lines), "zone"
    elseif p.windrowSource == "zone" then
        self:makeWindrowLines(p, "cp", true)
    end
end

function CinemaEditorScreen:removeZone(p, all)
    local zones = Z.decode(p.zones)
    if #zones == 0 then
        return
    end
    self:pushUndo()
    if all then
        zones = {}
    else
        table.remove(zones)
    end
    p.zones = Z.encode(zones)
    self:refreshZoneWindrows(p)
    self:markDirty()
    self:showMessage(t(all and "cine_msg_zoneCleared" or "cine_msg_zoneRemoved"))
end

---------------------------------------------------------------------------------------------------
-- kurz Courseplay

local function courseWidth(p, entry)
    local width = entry.width ~= nil and entry.width > 0 and entry.width or Z.DEFAULT_WIDTH
    return math.max(width + (p.zoneExtra or 0), 1)
end

local function courseLead(p)
    return p.zoneLead or E.ZONE_LEAD
end

-- Zóna sklizeno podle kurzu entry až do bodu hit (a o předsazení dál); nil, když z ní v poli nic nezbude.
local function courseZoneFor(p, entry, hit)
    -- sklizeno řeže hra jen v poli (limitToField), pruhy se tedy neřežou; jen úloha pole (náhrada) je řezat musí
    local zone = Z.courseZone(entry.lines, hit, courseWidth(p, entry), insideField(p, E.ZONE_EDGE_TOLERANCE), courseLead(p),
        Pr.cutAvailable())
    if zone ~= nil then
        zone.src = courseKey(entry.vehicle)
    end
    return zone
end

-- Sklizeno až do polohy každého stroje s kurzem pro pole: kombajn, který tam stojí, jen pokračuje.
function CinemaEditorScreen:zoneAtVehicles(p)
    local field = Pr.findField(p.field)
    local courses = field ~= nil and Pr.courses(field) or {}
    if #courses == 0 then
        self:showMessage(t("cine_msg_zoneNoCourse"))
        return
    end
    local zones, meters = {}, 0
    for _, entry in ipairs(courses) do
        local node = entry.vehicle.rootNode
        local x, _, z = getWorldTranslation(node)
        local hit = Z.project(entry.lines, x, z)
        local zone = hit ~= nil and courseZoneFor(p, entry, hit) or nil
        if zone ~= nil then
            zones[#zones + 1] = zone
            meters = meters + Z.length(zone.lines)
        end
    end
    if #zones == 0 then
        self:showMessage(t("cine_msg_zoneEmpty"))
    elseif self:addZones(p, zones) then
        self:showMessage(string.format(t("cine_msg_zoneVehicles"), #zones, meters))
    end
end

---------------------------------------------------------------------------------------------------
-- kreslení kliknutím

-- kind = "course" (klik na kurz), "cut" nebo "standing" (obdélník ze tří kliknutí)
function CinemaEditorScreen:startZoneDraw(p, kind)
    local d = { prop = p, kind = kind, points = {} }
    if kind == "course" then
        local field = Pr.findField(p.field)
        d.courses = field ~= nil and Pr.courses(field) or {}
        if #d.courses == 0 then
            self:showMessage(t("cine_msg_zoneNoCourse"))
            return
        end
    end
    self.picking, self.pendingAction, self.boxPlacing = false, nil, nil
    self.zoneDraw = d
    self:needCursor()
    self:showMessage(t(kind == "course" and "cine_msg_zoneClickCourse" or "cine_msg_zoneRect1"))
end

-- Kurz, ke kterému je (x, z) nejblíž: položka kurzu a zásah Z.project; nil bez kurzu.
local function nearestCourse(courses, x, z)
    local best, bestHit = nil, nil
    for _, entry in ipairs(courses) do
        local hit = Z.project(entry.lines, x, z)
        if hit ~= nil and (bestHit == nil or hit.d < bestHit.d) then
            best, bestHit = entry, hit
        end
    end
    return best, bestHit
end

function CinemaEditorScreen:finishCourseClick(d, x, z)
    local entry, hit = nearestCourse(d.courses, x, z)
    if entry == nil or hit.d > math.max(E.ZONE_FAR_MIN, courseWidth(d.prop, entry) * 2) then
        self:showMessage(t("cine_msg_zoneFar"))
        return
    end
    self.zoneDraw = nil
    local zone = courseZoneFor(d.prop, entry, hit)
    if zone == nil then
        self:showMessage(t("cine_msg_zoneEmpty"))
    elseif self:addZones(d.prop, { zone }) then
        self:showMessage(string.format(t("cine_msg_zoneCourse"), #zone.lines, Z.length(zone.lines)))
    end
end

function CinemaEditorScreen:finishRectClick(d, x, z)
    d.points[#d.points + 1] = { x, z }
    if #d.points < 3 then
        self:showMessage(t(#d.points == 1 and "cine_msg_zoneRect2" or "cine_msg_zoneRect3"))
        return
    end
    local a, b, c = d.points[1], d.points[2], d.points[3]
    local q = Z.rectQuad(a[1], a[2], b[1], b[2], c[1], c[2])
    local spacing = d.prop.windrowSpacing or Pr.WINDROW_SPACING
    local noClip = d.kind == "cut" and Pr.cutAvailable()
    local inside = insideField(d.prop, E.ZONE_EDGE_TOLERANCE)
    if q ~= nil and noClip and not inside((q[3] + q[5]) * 0.5, (q[4] + q[6]) * 0.5) then
        q = nil
    end
    local zone = q ~= nil and Z.rectZone(d.kind, q, inside, spacing, noClip) or nil
    if zone == nil then
        d.points = {}
        self:showMessage(t(q == nil and "cine_msg_zoneRectBad" or "cine_msg_zoneEmpty"))
        return
    end
    self.zoneDraw = nil
    if self:addZones(d.prop, { zone }) then
        self:showMessage(t(d.kind == "cut" and "cine_msg_zoneCutAdded" or "cine_msg_zoneStandingAdded"))
    end
end

-- Myš při kreslení zóny; true, když událost spotřebovala (kolečko a panely ne).
function CinemaEditorScreen:zoneMouseEvent(x, y, isDown, button)
    local d = self.zoneDraw
    if d == nil then
        return false
    end
    if button == Input.MOUSE_BUTTON_RIGHT then
        if isDown then
            self.zoneDraw = nil
            self:showMessage(t("cine_msg_zoneCancel"))
        end
        return true
    end
    if button ~= Input.MOUSE_BUTTON_LEFT or self:isOverPanels(x, y) then
        return false
    end
    if isDown then
        local tx, _, tz = W.pickTerrain(self.cam, x, y)
        if tx == nil then
            return true
        end
        if d.kind == "course" then
            self:finishCourseClick(d, tx, tz)
        else
            self:finishRectClick(d, tx, tz)
        end
    end
    return true
end

---------------------------------------------------------------------------------------------------
-- kreslení na pole

local function worldLine(cam, x1, z1, x2, z2, width, color)
    local sx1, sy1 = Cam.worldToScreen(cam, x1, W.terrainY(x1, z1) + 0.3, z1)
    local sx2, sy2 = Cam.worldToScreen(cam, x2, W.terrainY(x2, z2) + 0.3, z2)
    if sx1 ~= nil and sx2 ~= nil then
        E.gfx.line(sx1, sy1, sx2, sy2, width, color)
    end
end

local function quadOutline(cam, q, width, color)
    local c = Z.corners(q)
    for i = 1, 4 do
        local a, b = c[i], c[i % 4 + 1]
        worldLine(cam, a[1], a[2], b[1], b[2], width, color)
    end
end

-- Vybrané pole se zónami, nebo pole, do kterého se právě kreslí.
function CinemaEditorScreen:zoneShownProp()
    if self.zoneDraw ~= nil then
        return self.zoneDraw.prop
    end
    local p = self.activeProp ~= nil and self:props()[self.activeProp] or nil
    return p ~= nil and p.kind == "field" and p.zones ~= nil and p or nil
end

function CinemaEditorScreen:drawZones()
    local p = self:zoneShownProp()
    if p == nil then
        return
    end
    local cam = self.cam
    if self.zoneCache == nil or self.zoneCache.text ~= p.zones then
        self.zoneCache = { text = p.zones, zones = Z.decode(p.zones) }
    end
    for _, zone in ipairs(self.zoneCache.zones) do
        local color = zone.mode == "cut" and E.UI.pickHover or E.UI.pickBox
        for _, q in ipairs(zone.quads) do
            quadOutline(cam, q, 1.5, color)
        end
    end
    local d = self.zoneDraw
    if d == nil or self.mouseX == nil then
        return
    end
    local tx, _, tz = W.pickTerrain(cam, self.mouseX, self.mouseY)
    local hint
    if d.kind == "course" then
        for _, entry in ipairs(d.courses) do
            for _, l in ipairs(entry.lines) do
                worldLine(cam, l[1], l[2], l[3], l[4], 1.5, E.ZONE_CP_COLOR)
            end
        end
        local entry, hit
        if tx ~= nil then
            entry, hit = nearestCourse(d.courses, tx, tz)
        end
        if entry ~= nil then
            local done = Z.upTo(entry.lines, hit, courseLead(p))
            for _, l in ipairs(done) do
                worldLine(cam, l[1], l[2], l[3], l[4], 3, E.UI.pickHover)
            end
            hint = string.format(t("cine_zone_hintCourse"), Z.length(done))
        end
    elseif tx ~= nil then
        local color = d.kind == "cut" and E.UI.pickHover or E.UI.pickBox
        local a, b = d.points[1], d.points[2]
        if a ~= nil and b == nil then
            worldLine(cam, a[1], a[2], tx, tz, 3, color)
        elseif b ~= nil then
            local q = Z.rectQuad(a[1], a[2], b[1], b[2], tx, tz)
            if q ~= nil then
                quadOutline(cam, q, 3, color)
            else
                worldLine(cam, a[1], a[2], b[1], b[2], 3, color)
            end
        end
    end
    if hint ~= nil then
        E.gfx.text(self.mouseX, self.mouseY + 0.025, E.TEXT_SIZE, hint, E.UI.pickHover, RenderText.ALIGN_CENTER, true)
    end
end

---------------------------------------------------------------------------------------------------
-- menu

function CinemaEditorScreen:openZoneMenu(p, change)
    local function summary()
        local cut, standing, quads = Z.summary(Z.decode(p.zones))
        return string.format(t("cine_zone_summary"), cut, standing, quads)
    end
    local items = {
        E.menuItem(summary, function() end, { disabled = true }),
        E.menuItem(t("cine_zone_course"), function(s) s:startZoneDraw(p, "course") end),
        E.menuItem(t("cine_zone_courseHere"), function(s) s:zoneAtVehicles(p) end),
        E.stepItem(function() return string.format(t("cine_zone_lead"), courseLead(p)) end,
            function(s) change(s, function() p.zoneLead = math.min(courseLead(p) + 1, E.ZONE_LEAD_MAX) end) end,
            function(s) change(s, function() p.zoneLead = math.max(courseLead(p) - 1, 0) end) end),
        E.stepItem(function() return string.format(t("cine_zone_extra"), p.zoneExtra or 0) end,
            function(s) change(s, function() p.zoneExtra = math.min((p.zoneExtra or 0) + E.ZONE_EXTRA_STEP, E.ZONE_EXTRA_MAX) end) end,
            function(s) change(s, function() p.zoneExtra = math.max((p.zoneExtra or 0) - E.ZONE_EXTRA_STEP, -E.ZONE_EXTRA_MAX) end) end),
        E.menuItem(t("cine_zone_rectCut"), function(s) s:startZoneDraw(p, "cut") end),
        E.menuItem(t("cine_zone_rectStanding"), function(s) s:startZoneDraw(p, "standing") end),
        E.menuItem(t("cine_zone_windrows"), function(s)
            change(s, function() s:makeWindrowLines(p, "zone") end)
        end, { disabled = #Z.cutLines(Z.decode(p.zones)) == 0 }),
        E.menuItem(t("cine_zone_removeLast"), function(s) s:removeZone(p, false) end, { disabled = p.zones == nil }),
        E.menuItem(t("cine_zone_removeAll"), function(s) s:removeZone(p, true) end, { disabled = p.zones == nil }),
    }
    self:openMenu(string.format(t("cine_zone_title"), p.name or "?"), items, self.mouseX or 0.5, self.mouseY or 0.5)
end
