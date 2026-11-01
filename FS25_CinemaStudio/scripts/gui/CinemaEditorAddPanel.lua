-- Panel Přidat (tlačítko + Akce na liště osy): dlaždice akcí kamery na ukazatel, rozdělené podle toho, kdo řídí pohyb kamery
-- (režim sám / tvoje K-framy / nikdo). Nahoře cíl akcí; panel roste nahoru od tlačítka a drží se pravého okraje obrazovky.
-- Je to druh menu (self.menu.panel = "add"): Esc a klik mimo ho zavřou stejně.

local E = CinemaEditorScreen
local W = CinemaWorld
local Mo = CinemaModes
local S = CinemaShot
local rect, text = E.gfx.rect, E.gfx.text

E.ADD_W = 0.3
E.ADD_HEAD = 0.034
E.ADD_GROUP = 0.026
E.ADD_TILE = 0.04
E.ADD_GAP = 0.004
E.ADD_FOOT = 0.03
E.ADD_PAD = 0.008
E.ADD_COLS = 2

local function t(key)
    return g_i18n:getText(key)
end

local function modeTile(mode)
    return { id = mode, run = function(s) s:addModeAction(mode) end }
end

E.ADD_GROUPS = {
    {
        title = "cine_add_g_auto",
        tiles = {
            modeTile("orbit"),
            { id = "follow", run = function(s, x, y) s:openFollowSideMenu(x, y) end },
            modeTile("dronie"), modeTile("rocket"), modeTile("helix"), modeTile("approach"), modeTile("boomerang"),
            modeTile("parallel"), modeTile("topdown"), modeTile("pair"),
        },
    },
    {
        title = "cine_add_g_onboard",
        tiles = {
            modeTile("mount"), modeTile("vehicleCam"),
        },
    },
    {
        title = "cine_add_g_keys",
        tiles = {
            { id = "flight", kbd = "K", run = function(s) s:onActionKeyAdd() end },
            modeTile("spotlight"),
        },
    },
    {
        title = "cine_add_g_stand",
        tiles = {
            modeTile("pass"),
        },
    },
    {
        title = "cine_add_g_still",
        tiles = {
            { id = "static", run = function(s) s:addStaticAction() end },
            { id = "lookAt", run = function(s) s:addLookAtAction() end },
        },
    },
}

function E.addTileName(id)
    return "cine_add_" .. id
end

-- Cíl akcí z panelu (uid vozidla nebo cíl postavy): naposledy vybraný, jinak herec vybraného řádku, jinak první herec.
function CinemaEditorScreen:getAddTarget()
    local shot = self.shot
    if self.addTarget ~= nil and self:targetName(self.addTarget) ~= nil then
        return self.addTarget
    end
    for _, i in ipairs({ self.activeTarget, 1 }) do
        local actor = shot.actors[i]
        if actor ~= nil and CinemaPerson.isPerson(actor) then
            return S.personTarget(shot, actor)
        end
        local first = actor ~= nil and actor.start ~= nil and actor.start.entries[1] or nil
        if first ~= nil and W.find(first.uid) ~= nil then
            return first.uid
        end
    end
    return nil
end

-- Bez cíle se objekt vybere myší ve scéně a akce se dokončí po kliknutí na něj.
local function pickFor(self, pending)
    self.pendingAction = pending
    self.picking = true
    self:needCursor()
    self:showMessage(t(pending.target and "cine_msg_pickTarget" or "cine_msg_pickForAction"))
end

function CinemaEditorScreen:addModeAction(mode, side)
    self.lastAction = { mode = mode, side = side }
    local target = self:getAddTarget()
    if target == nil then
        pickFor(self, { mode = mode, side = side })
        return
    end
    local v = W.find(target)
    if (mode == "mount" or mode == "vehicleCam") and v == nil then
        self:showMessage(t("cine_msg_needVehicle"))
    elseif mode == "mount" then
        self:createMountTrack(v)
    elseif mode == "vehicleCam" then
        self:openVehicleCamMenu(v, self.mouseX or 0.5, self.mouseY or 0.5)
    elseif mode == "pair" then
        self:openPairMenu(target, self.mouseX or 0.5, self.mouseY or 0.5)
    else
        self:createTrackOn(mode, target, side)
    end
end

function CinemaEditorScreen:addStaticAction()
    self.lastAction = { mode = "static" }
    self:createStaticTrack()
end

function CinemaEditorScreen:addLookAtAction()
    local target = self:getAddTarget()
    if target == nil then
        pickFor(self, { focus = true })
        return
    end
    self:setFocusHere(target)
end

function CinemaEditorScreen:repeatLastAction()
    local last = self.lastAction
    if last == nil then
        return
    end
    if last.mode == "static" then
        self:addStaticAction()
    else
        self:addModeAction(last.mode, last.side)
    end
end

function CinemaEditorScreen:openFollowSideMenu(x, y)
    local items = {}
    for _, side in ipairs(Mo.FOLLOW_ORDER) do
        items[#items + 1] = { text = t("cine_follow_" .. side), action = function(s) s:addModeAction("follow", side) end }
    end
    self:openMenu(t("cine_mode_follow"), items, x, y)
end

function CinemaEditorScreen:openAddTargetMenu(x, y)
    local items = {}
    for _, c in ipairs(self:focusCandidates()) do
        items[#items + 1] = { text = c.label, action = function(s)
            s.addTarget = c.target
            s:openAddPanel()
        end }
    end
    items[#items + 1] = { text = t("cine_add_pickTarget"), action = function(s) pickFor(s, { target = true }) end }
    self:openMenu(t("cine_add_targetTitle"), items, x, y)
end

-- Tlačítko + Akce: na řádku kamery panel Přidat, na řádku vozidla akce vozidla na ukazatel.
-- Řádek, ke kterému tlačítko + Akce / + Kamera přidává: "camera", "vehicle", "person" nebo "object".
function CinemaEditorScreen:addRowKind()
    if self.objectFocus and self.activeObject ~= nil and self:objects()[self.activeObject] ~= nil then
        return "object"
    end
    local actor = self.activeTarget > 0 and self.shot.actors[self.activeTarget] or nil
    if actor == nil then
        return "camera"
    end
    return CinemaPerson.isPerson(actor) and "person" or "vehicle"
end

function CinemaEditorScreen:onAddButton(x, y, entry)
    local kind = self:addRowKind()
    if kind == "object" then
        self:openObjectActionMenu(self.activeObject, x, y)
        return
    end
    local i = self.activeTarget
    local actor = self.shot.actors[i]
    if kind ~= "camera" then
        local at = math.max(CinemaActions.minTime(actor), math.floor((self.playhead - (actor.delay or 0)) * 10 + 0.5) / 10)
        if kind == "person" then
            self:openPersonActionMenu(i, at, x, y)
        else
            self:openVehicleActionMenu(i, at, x, y)
        end
        return
    end
    self:openAddPanel(entry ~= nil and entry.x + entry.w or nil)
end

function CinemaEditorScreen:openAddPanel(anchorX)
    self.addAnchor = anchorX or self.addAnchor or E.BAR_X1
    self.menu = { panel = "add", title = t("cine_tb_addCamera"), items = {}, x = 0, y = 0 }
    self.drag = nil
end

local function targetLabel(self)
    local target = self:getAddTarget()
    return string.format(t("cine_add_target"), target ~= nil and self:targetName(target) or t("cine_add_noTarget"))
end

-- Rozvržení: rámeček, nadpisy skupin a zásahy { kind = "target" | "tile", tile, x, y, w, h }.
function CinemaEditorScreen:addPanelLayout()
    local h = E.ADD_HEAD + E.ADD_FOOT + E.ADD_PAD
    for _, group in ipairs(E.ADD_GROUPS) do
        h = h + E.ADD_GROUP + math.ceil(#group.tiles / E.ADD_COLS) * (E.ADD_TILE + E.ADD_GAP)
    end
    local w = E.ADD_W
    local x = math.max(0.005, math.min(self.addAnchor or E.BAR_X1, 0.995) - w)
    local y = math.max(0.005, math.min(self:getMenuFloor(), E.TOP_LIMIT - h))
    local top = y + h
    local headY = top - E.ADD_HEAD
    local tw = math.min(getTextWidth(E.MENU_TEXT * 0.9, targetLabel(self)) + 2 * E.ADD_PAD, w * 0.55)
    local hits = { { kind = "target", x = x + w - E.ADD_PAD * 0.5 - tw, y = headY + 0.005, w = tw, h = E.ADD_HEAD - 0.01 } }
    local labels = {}
    local tileW = (w - 2 * E.ADD_PAD - (E.ADD_COLS - 1) * E.ADD_GAP) / E.ADD_COLS
    local cy = headY
    for _, group in ipairs(E.ADD_GROUPS) do
        cy = cy - E.ADD_GROUP
        labels[#labels + 1] = { text = t(group.title), x = x + E.ADD_PAD, y = cy + E.ADD_GROUP * 0.3 }
        for k, tile in ipairs(group.tiles) do
            local col = (k - 1) % E.ADD_COLS
            local row = math.floor((k - 1) / E.ADD_COLS)
            hits[#hits + 1] = { kind = "tile", tile = tile, x = x + E.ADD_PAD + col * (tileW + E.ADD_GAP),
                y = cy - (row + 1) * (E.ADD_TILE + E.ADD_GAP) + E.ADD_GAP, w = tileW, h = E.ADD_TILE }
        end
        cy = cy - math.ceil(#group.tiles / E.ADD_COLS) * (E.ADD_TILE + E.ADD_GAP)
    end
    return { x = x, y = y, w = w, h = h, headY = headY, hits = hits, labels = labels }
end

local function inside(r, px, py)
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

-- Střed dlaždice s id (pro testy a klávesnici); nil, když panel takovou nemá.
function CinemaEditorScreen:getAddTilePoint(id)
    for _, hit in ipairs(self:addPanelLayout().hits) do
        if (hit.kind == "tile" and hit.tile.id == id) or (hit.kind == id) then
            return hit.x + hit.w * 0.5, hit.y + hit.h * 0.5
        end
    end
    return nil
end

function CinemaEditorScreen:addPanelMouseEvent(px, py, isDown, button)
    local layout = self:addPanelLayout()
    local index = nil
    for i, hit in ipairs(layout.hits) do
        if inside(hit, px, py) then
            index = i
        end
    end
    self.menu.hover = index
    if not isDown or button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN then
        return
    end
    if button ~= Input.MOUSE_BUTTON_LEFT or not inside(layout, px, py) then
        self.menu = nil
        return
    end
    if index == nil then
        return
    end
    local hit = layout.hits[index]
    E.playSound("CLICK")
    self.menu = nil
    if hit.kind == "target" then
        self:openAddTargetMenu(hit.x, hit.y)
    else
        hit.tile.run(self, hit.x, hit.y + hit.h)
    end
end

local function fitSize(s, size, width)
    local w = getTextWidth(size, s)
    return w > width and size * width / w or size
end

function CinemaEditorScreen:drawAddPanel()
    local ui = E.UI
    local px = g_pixelSizeScaledX
    local L = self:addPanelLayout()
    local hover = self.menu.hover
    rect(L.x - 0.002, L.y - 0.003, L.w + 0.004, L.h + 0.006, { 0, 0, 0, 1 })
    rect(L.x, L.y, L.w, L.h, ui.panel)
    rect(L.x, L.headY, L.w, E.ADD_HEAD, ui.highlight)
    local size = E.MENU_TEXT
    text(L.x + E.ADD_PAD, L.headY + E.ADD_HEAD * 0.5 - size * 0.38, size * 1.05,
        E.upper(string.format(t("cine_add_title"), self.playhead)), ui.text, RenderText.ALIGN_LEFT, true)
    for _, label in ipairs(L.labels) do
        text(label.x, label.y, size * 0.75, E.upper(label.text), ui.dim, RenderText.ALIGN_LEFT, true)
    end
    local last = self.lastAction ~= nil and self.lastAction.mode or nil
    for i, hit in ipairs(L.hits) do
        local hovered = i == hover
        if hit.kind == "target" then
            rect(hit.x, hit.y, hit.w, hit.h, hovered and { 0, 0, 0, 0.6 } or { 0, 0, 0, 0.35 })
            local ts = fitSize(targetLabel(self), size * 0.9, hit.w - 2 * E.ADD_PAD)
            text(hit.x + E.ADD_PAD, hit.y + hit.h * 0.5 - ts * 0.38, ts, targetLabel(self), ui.text)
        else
            local tile = hit.tile
            rect(hit.x, hit.y, hit.w, hit.h, hovered and ui.highlight or ui.row)
            if hovered or tile.id == last then
                rect(hit.x, hit.y, 3 * px, hit.h, hovered and ui.text or ui.accent)
            end
            local inner = hit.w - 2 * E.ADD_PAD
            local name = t(E.addTileName(tile.id))
            text(hit.x + E.ADD_PAD, hit.y + hit.h - size * 1.25, fitSize(name, size, inner), name, ui.text, RenderText.ALIGN_LEFT, true)
            local desc = t(E.addTileName(tile.id) .. "_d")
            local ds = fitSize(desc, size * 0.78, inner)
            text(hit.x + E.ADD_PAD, hit.y + hit.h * 0.16, ds, desc, hovered and ui.text or ui.dim)
            if tile.kbd ~= nil then
                local ks = size * 0.75
                local kw = getTextWidth(ks, tile.kbd) + 2 * E.KBD_PAD
                local kx, ky = hit.x + hit.w - E.ADD_PAD - kw, hit.y + hit.h - size * 1.35
                rect(kx, ky, kw, size * 1.05, hovered and ui.kbdLit or ui.kbd)
                text(kx + kw * 0.5, ky + size * 0.2, ks, tile.kbd, hovered and ui.text or ui.accent, RenderText.ALIGN_CENTER, true)
            end
        end
    end
    text(L.x + E.ADD_PAD, L.y + E.ADD_PAD, size * 0.8, t("cine_add_foot"), ui.dim)
end
