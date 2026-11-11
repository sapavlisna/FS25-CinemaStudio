-- Krabice v editoru: tlačítko na liště s menu, přidávání věcí klikáním ve scéně (jako T, výběr zůstane zapnutý) a pokládání:
-- pod kurzorem jsou obrysy věcí na zemi, kolečko celek natáčí (Shift jemně), levé tlačítko položí, pravé nebo Esc zruší.

local E = CinemaEditorScreen
local B = CinemaBox
local W = CinemaWorld
local Pr = CinemaProps
local Cam = CinemaCamera

E.BOX_ROT_STEP = math.rad(15)
E.BOX_ROT_FINE = math.rad(3)

local function t(key)
    return g_i18n:getText(key)
end

function E:boxLabel()
    return string.format(t("cine_box_tb"), B.count())
end

function E:openBoxMenu(x, y)
    local items = {
        { text = t("cine_box_pick"), action = function(s) s:startBoxPick() end },
        { text = string.format(t("cine_box_place"), B.count()), action = function(s) s:startBoxPlace() end, disabled = B.count() == 0 },
        { text = t("cine_box_clear"), action = function() B.clear() end, disabled = B.count() == 0 },
    }
    self:openMenu(self:boxLabel(), items, x, y)
end

-- přidávání

function E:startBoxPick()
    self.boxPlacing = nil
    self.picking = true
    self.pendingAction = { box = true }
    self:needCursor()
    self:showMessage(t("cine_msg_boxPick"))
end

-- Klik ve scéně při přidávání: balík nebo vozidlo pod kurzorem do krabice (podruhé ven). Výběr zůstane zapnutý.
function E:boxPickAt(x, y)
    local bale = Pr.baleAt(self.cam, x, y)
    local name, inBox
    if bale ~= nil then
        inBox, name = B.toggleBale(bale), Pr.baleName(bale)
    else
        local c = W.candidateAt(self.pickCandidates or W.candidates(self.cam), x, y)
        if c == nil or c.vehicle == nil then
            return
        end
        inBox, name = B.toggleVehicle(c.vehicle), W.name(W.rootOf(c.vehicle))
    end
    self:showMessage(string.format(t(inBox and "cine_msg_boxIn" or "cine_msg_boxOut"), name, B.count()))
end

-- Při přidávání: obrysy vozidel (v krabici zvýrazněné) a značky balíků.
function E:drawBoxPick()
    local gfx = E.gfx
    local list = W.candidates(self.cam)
    self.pickCandidates = list
    local bale = Pr.baleAt(self.cam, self.mouseX, self.mouseY)
    local hover = bale == nil and W.candidateAt(list, self.mouseX, self.mouseY) or nil
    for _, c in ipairs(list) do
        local b = c.box
        local boxed = B.hasVehicle(c.vehicle)
        local color = (c == hover and E.UI.pickHover) or (boxed and E.UI.boxed) or E.UI.pickBox
        gfx.outline(b[1], b[2], b[3], b[4], (c == hover or boxed) and 3 or 1.5, color)
        if c == hover then
            gfx.text((b[1] + b[3]) * 0.5, b[4] + 0.01, E.TEXT_SIZE, W.name(W.rootOf(c.vehicle)), E.UI.pickHover, RenderText.ALIGN_CENTER, true)
        end
    end
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    for _, c in ipairs(Pr.baleCandidates(self.cam, self.mouseX, self.mouseY)) do
        local boxed = B.has("bale", Pr.baleUid(c.bale))
        local isHover = c.bale == bale
        local r = (isHover or boxed) and 10 or 6
        gfx.outline(c.sx - r * px, c.sy - r * py, c.sx + r * px, c.sy + r * py, (isHover or boxed) and 3 or 1.5,
            (isHover and E.UI.pickHover) or (boxed and E.UI.boxed) or E.UI.pickBox)
    end
end

-- pokládání

-- set: co se položí (bez něj obsah krabice).
function E:startBoxPlace(set)
    local fromBox = set == nil
    set = set or B.collect()
    if B.isEmpty(set) then
        self:showMessage(t("cine_msg_boxEmpty"))
        return
    end
    local cx, cz = B.center(set)
    self.picking = false
    self.pendingAction = nil
    self.boxPlacing = { set = set, fromBox = fromBox, rot = 0, cx = cx, cz = cz, outlines = B.outlines(set) }
    self:needCursor()
    self:showMessage(t("cine_msg_pickTeleport"))
end

-- Myš při pokládání; true, když událost spotřebovala.
function E:boxMouseEvent(x, y, isDown, button)
    local placing = self.boxPlacing
    if placing == nil or not isDown then
        return placing ~= nil
    end
    if button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN then
        local step = E.isShift() and E.BOX_ROT_FINE or E.BOX_ROT_STEP
        placing.rot = placing.rot + (button == Input.MOUSE_BUTTON_WHEEL_UP and step or -step)
    elseif button == Input.MOUSE_BUTTON_RIGHT then
        self.boxPlacing = nil
    elseif button == Input.MOUSE_BUTTON_LEFT and not self:isOverPanels(x, y) then
        local tx, _, tz = W.pickTerrain(self.cam, x, y)
        if tx ~= nil then
            self:placeBoxAt(tx, tz)
        end
    end
    return true
end

function E:placeBoxAt(tx, tz)
    local placing = self.boxPlacing
    self.boxPlacing = nil
    local moved, why = B.place(placing.set, tx, tz, placing.rot)
    if moved == nil then
        self:showMessage(t(why == "notServer" and "cine_msg_actorNotServer" or "cine_msg_actorMissing"))
    elseif placing.fromBox and moved > 0 then
        -- věci z krabice jsou vybalené: krabice je prázdná (kdyby se nic nepřeneslo, zůstane, jak byla)
        B.clear()
        self:showMessage(string.format(t("cine_msg_boxPlacedEmpty"), moved))
    else
        self:showMessage(string.format(t("cine_msg_boxPlaced"), moved))
    end
end

-- Obrysy věcí na zemi tam, kam by padly pod kurzorem.
function E:drawBoxPlace()
    local placing = self.boxPlacing
    local tx, _, tz = W.pickTerrain(self.cam, self.mouseX, self.mouseY)
    if tx == nil then
        return
    end
    for _, quad in ipairs(placing.outlines) do
        local points = {}
        for i, corner in ipairs(quad) do
            local x, _, z = B.pose(placing.cx, placing.cz, tx, tz, placing.rot, corner[1], 0, corner[2])
            local sx, sy = Cam.worldToScreen(self.cam, x, W.terrainY(x, z) + 0.15, z)
            if sx == nil then
                points = nil
                break
            end
            points[i] = { sx, sy }
        end
        for i = 1, points ~= nil and #points or 0 do
            local a, b = points[i], points[i % #points + 1]
            E.gfx.line(a[1], a[2], b[1], b[2], 2, E.UI.boxed)
        end
    end
    E.gfx.text(self.mouseX, self.mouseY + 0.02, E.TEXT_SIZE, string.format("%.0f°", math.deg(placing.rot)), E.UI.boxed,
        RenderText.ALIGN_CENTER, true)
end
