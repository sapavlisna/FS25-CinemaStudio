-- Kontextové menu editoru (pravé tlačítko na panelu, klik na objekt v režimu výběru): seznam položek u kurzoru,
-- najetí zvýrazní, klik provede. Položky s keepOpen nechají menu otevřené (opakované +/−) a text se překreslí.

local E = CinemaEditorScreen
local M = CinemaMath
local S = CinemaShot
local W = CinemaWorld
local Mo = CinemaModes
local R = CinemaRoute
local A = CinemaActions
local Env = CinemaEnvironment

E.MENU_TEXT = 0.015
E.MENU_LINE = 0.028
E.MENU_PAD = 0.008
E.MENU_ARROW = 0.018 -- místo vpravo na šipku položky s podmenu
E.DOCK_MARGIN = 0.004
E.DOCK_TOP = 0.95 -- pod horní lištou

local function t(key)
    return g_i18n:getText(key)
end

-- opts.back: položka s výběrem z několika možností; levé tlačítko = action (další), pravé = back (předchozí), menu zůstane.
local function item(text, action, opts)
    local entry = { text = text, action = action }
    if opts ~= nil then
        entry.keepOpen, entry.disabled, entry.submenu, entry.back = opts.keepOpen, opts.disabled, opts.submenu, opts.back
        if entry.back ~= nil then
            entry.keepOpen = true
        end
    end
    return entry
end
E.menuItem = item

-- Hodnota, kterou levé tlačítko zvýší (up) a pravé sníží (down); menu zůstane otevřené.
local function stepItem(text, up, down, opts)
    opts = opts or {}
    opts.back = down
    return item(text, up, opts)
end
E.stepItem = stepItem

-- Oddělovač skupin položek (nedá se zvolit).
local function separator()
    return { text = "", separator = true, disabled = true }
end

-- Položka, která otevře podmenu se skupinou položek (Další, Nastavení…) na stejném místě a s nadpisem menu.
local function groupItem(label, title, items, x, y)
    local entry = item(label, function(s) s:openMenu(title, items, x, y) end, { submenu = true })
    entry.group = true
    return entry
end

local function itemText(entry)
    if type(entry.text) == "function" then
        return entry.text()
    end
    return entry.text
end

-- Menu otevřené z panelu s osou vyrostou nad ním (nepřekrývají jeho texty), jinak od kurzoru dolů. Položky se píšou
-- od nejpoužívanější; menu nad osou je má obráceně, aby nejpoužívanější byla dole u kurzoru (a mazání nahoře, daleko).
-- Při sestavování bočního panelu se menu jen zachytí a neotevře.
function CinemaEditorScreen:openMenu(title, items, x, y)
    if self.capturing then
        self.captured = { title = title, items = items }
        return
    end
    local above = y < self:getPanelTop()
    if above then
        local reversed = {}
        for k = #items, 1, -1 do
            reversed[#reversed + 1] = items[k]
        end
        items = reversed
    end
    self.menu = { title = title, items = items, x = x, y = y, hover = nil, above = above }
    self.drag = nil
end

-- Položka nabídky, která přepíná boční panel: vypnutý → vlevo → vpravo (stejně jako klávesa P).
function E.dockItem()
    return item(function() return t("cine_menu_dock_" .. (E.INSTANCE ~= nil and E.INSTANCE.dock or "off")) end,
        function(s) s:onActionDock() end, { keepOpen = true })
end

-- Šířka menu podle nejdelší položky; položky s podmenu mají místo na šipku.
function E.menuWidth(title, items)
    local width = getTextWidth(E.MENU_TEXT * 1.05, itemText({ text = title }))
    for _, entry in ipairs(items) do
        local w = getTextWidth(E.MENU_TEXT, itemText(entry)) + ((entry.submenu or entry.back ~= nil) and E.MENU_ARROW * 2 or 0)
        width = math.max(width, w)
    end
    return width + 2 * E.MENU_PAD
end

-- Spodní mez menu a bočního panelu: nad osou (a nad křivkami, když jsou otevřené).
function CinemaEditorScreen:getMenuFloor()
    return self:getPanelTop() + (self.curves and E.CURVE_HEIGHT or 0) + 0.004
end

-- Mřížka položek: nevejdou-li se pod sebe do výšky maxHeight, rozdělí se do sloupců (menu nikdy nepřekryje osu).
function E.menuGrid(title, items, maxHeight)
    local colW = E.menuWidth(title, items)
    local fit = math.max(math.floor((maxHeight - E.MENU_PAD) / E.MENU_LINE) - 1, 3)
    local cols = math.max(math.ceil(#items / fit), 1)
    local perCol = math.max(math.ceil(#items / cols), 1)
    return { cols = cols, perCol = perCol, colW = colW, width = cols * colW, height = (perCol + 1) * E.MENU_LINE + E.MENU_PAD }
end

-- Číslo položky pod bodem (px, py) v rámečku x, y, h s mřížkou grid; řádek 0 je nadpis.
function E.menuGridItemAt(grid, count, x, y, h, px, py)
    local row = math.floor((y + h - py) / E.MENU_LINE)
    if row < 1 or row > grid.perCol then
        return nil
    end
    local col = math.floor((px - x) / grid.colW)
    local i = col * grid.perCol + row
    if col < 0 or col >= grid.cols or i > count then
        return nil
    end
    return i
end

-- Střed položky i; x, y, h je rámeček menu.
function E.menuGridItemCenter(grid, x, y, h, i)
    local col = math.floor((i - 1) / grid.perCol)
    local row = (i - 1) % grid.perCol + 1
    return x + (col + 0.5) * grid.colW, y + h - (row + 0.5) * E.MENU_LINE
end

-- Obdélník menu (x, y, w, h) a mřížka; menu roste od kurzoru dolů, nevyleze z obrazovky a nepřekryje osu.
function CinemaEditorScreen:getMenuLayout()
    local menu = self.menu
    local floor = self:getMenuFloor()
    local grid = E.menuGrid(menu.title, menu.items, E.TOP_LIMIT - floor)
    local x = M.clamp(menu.x, 0.005, 0.995 - grid.width)
    if menu.above then
        return x, floor, grid.width, grid.height, grid
    end
    local top = M.clamp(menu.y, floor + grid.height, E.TOP_LIMIT)
    return x, top - grid.height, grid.width, grid.height, grid
end

function CinemaEditorScreen:getMenuItemPoint(i)
    local x, y, _, h, grid = self:getMenuLayout()
    return E.menuGridItemCenter(grid, x, y, h, i)
end

function CinemaEditorScreen:menuItemAt(px, py)
    local x, y, w, h, grid = self:getMenuLayout()
    if px < x or px > x + w or py < y or py > y + h then
        return nil, false
    end
    return E.menuGridItemAt(grid, #self.menu.items, x, y, h, px, py), true
end

function CinemaEditorScreen:menuMouseEvent(posX, posY, isDown, isUp, button)
    if self.menu.panel == "add" then
        self:addPanelMouseEvent(posX, posY, isDown, button)
        return
    end
    local i, inside = self:menuItemAt(posX, posY)
    self.menu.hover = i
    if not isDown or button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN then
        return
    end
    local entry = inside and i ~= nil and self.menu.items[i] or nil
    local back = button == Input.MOUSE_BUTTON_RIGHT and entry ~= nil and entry.back ~= nil
    if (button ~= Input.MOUSE_BUTTON_LEFT and not back) or not inside then
        self.menu = nil
        return
    end
    if entry == nil or entry.disabled then
        return
    end
    if back then
        E.playSound("CLICK")
        entry.back(self)
        return
    end
    local menu = self.menu
    if not entry.keepOpen then
        self.menu = nil
    end
    E.playSound("CLICK")
    entry.action(self)
    if entry.keepOpen and self.menu == menu then
        self.menu.hover = i
    end
end

-- Rámeček s nadpisem a položkami; položky s podmenu mají vpravo šipku.
function CinemaEditorScreen:drawMenuBox(x, y, w, h, title, items, hover, alpha, grid)
    local ui = E.UI
    local py = g_pixelSizeScaledY
    drawFilledRect(x - 0.002, y - 0.003, w + 0.004, h + 0.006, 0, 0, 0, alpha)
    drawFilledRect(x, y, w, h, ui.panel[1], ui.panel[2], ui.panel[3], alpha)
    local hl = ui.highlight
    drawFilledRect(x, y + h - E.MENU_LINE, w, E.MENU_LINE, hl[1], hl[2], hl[3], alpha)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(ui.text[1], ui.text[2], ui.text[3], 1)
    renderText(x + E.MENU_PAD, y + h - E.MENU_LINE + E.MENU_PAD * 0.9, E.MENU_TEXT * 1.05, E.upper(itemText({ text = title })))
    for i, entry in ipairs(items) do
        local col = math.floor((i - 1) / grid.perCol)
        local colX = x + col * grid.colW
        local rowY = y + h - ((i - 1) % grid.perCol + 2) * E.MENU_LINE
        if entry.separator then
            local sc = ui.separatorLine
            drawFilledRect(colX + E.MENU_PAD, rowY + E.MENU_LINE * 0.5, grid.colW - 2 * E.MENU_PAD, py, sc[1], sc[2], sc[3], sc[4])
        elseif i == hover and not entry.disabled then
            drawFilledRect(colX, rowY, grid.colW, E.MENU_LINE, hl[1], hl[2], hl[3], 1)
        end
        local c = entry.disabled and ui.dim or ui.text
        setTextColor(c[1], c[2], c[3], c[4] or 1)
        setTextBold(false)
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(colX + E.MENU_PAD, rowY + E.MENU_PAD * 0.9, E.MENU_TEXT, itemText(entry))
        if entry.submenu or entry.back ~= nil then
            setTextBold(true)
            setTextAlignment(RenderText.ALIGN_RIGHT)
            renderText(colX + grid.colW - E.MENU_PAD, rowY + E.MENU_PAD * 0.9, E.MENU_TEXT, entry.back ~= nil and "< >" or ">")
        end
    end
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

function CinemaEditorScreen:drawMenu()
    if self.menu.panel == "add" then
        self:drawAddPanel()
        return
    end
    local x, y, w, h, grid = self:getMenuLayout()
    self:drawMenuBox(x, y, w, h, self.menu.title, self.menu.items, self.menu.hover, 1, grid)
end

---------------------------------------------------------------------------------------------------
-- boční panel: nabídka vybraného řádku (kamera → nabídka záběru, vozidlo → nabídka vozidla) stále na očích

-- Položky panelu se sestavují znovu při každém kreslení i kliknutí, takže nikdy neodkazují na starý stav záběru.
function CinemaEditorScreen:buildDock(x, y)
    self.capturing, self.captured = true, nil
    if self.activeTarget > 0 and self.shot.actors[self.activeTarget] ~= nil then
        self:openActorMenu(self.activeTarget, x, y)
    else
        self:openShotMenu(x, y)
    end
    self.capturing = false
    local captured = self.captured
    self.captured = nil
    return captured
end

-- x, y (dolní okraj), šířka, výška a obsah panelu.
function CinemaEditorScreen:getDockLayout()
    local content = self:buildDock(0.3, E.DOCK_TOP)
    local grid = E.menuGrid(content.title, content.items, E.DOCK_TOP - self:getMenuFloor())
    local x = self.dock == "left" and E.DOCK_MARGIN or 1 - E.DOCK_MARGIN - grid.width
    return x, E.DOCK_TOP - grid.height, grid.width, grid.height, content, grid
end

function CinemaEditorScreen:drawDock()
    local x, y, w, h, content, grid = self:getDockLayout()
    -- s rozhlížením myší je panel jen k nahlédnutí (kurzor zapne F nebo Alt)
    self:drawMenuBox(x, y, w, h, content.title, content.items, not self.freeLook and self.dockHover or nil, self.freeLook and 0.8 or 1, grid)
end

-- Klik do panelu provede položku; podmenu se otevře vedle panelu u kliknuté položky.
-- Vrací true, když událost patřila panelu.
function CinemaEditorScreen:dockMouseEvent(px, py, isDown, button)
    if self.dock == nil or self.freeLook or self.clean then
        return false
    end
    local x, y, w, h, _, grid = self:getDockLayout()
    if px < x or px > x + w or py < y or py > y + h then
        self.dockHover = nil
        return false
    end
    local i = E.menuGridItemAt(grid, grid.perCol * grid.cols, x, y, h, px, py)
    self.dockHover = i
    if isDown and button == Input.MOUSE_BUTTON_LEFT and i ~= nil then
        local sx = self.dock == "left" and x + w + 0.005 or x - 0.26
        local _, cy = E.menuGridItemCenter(grid, x, y, h, i)
        local content = self:buildDock(sx, cy + E.MENU_LINE * 0.5)
        local entry = content ~= nil and content.items[i] or nil
        if entry ~= nil and not entry.disabled then
            entry.action(self)
        end
    end
    return true
end

---------------------------------------------------------------------------------------------------
-- obsah menu

function CinemaEditorScreen:openContextMenu(x, y)
    local hit = self:hitPanels(x, y)
    if hit == nil then
        return
    end
    if hit.kind == "curveHandle" then
        -- pravé tlačítko na táhle vrátí výchozí délku rozjezdu / dojezdu
        self:pushUndo()
        S.setKeyInfluence(self.shot, hit.seg.track.keys[hit.index], hit.side, nil)
        self:markDirty()
    elseif hit.kind == "key" or hit.kind == "curveKey" then
        self:ctxSelect("key", hit.seg.track.keys[hit.index])
        self:openKeyMenu(hit.seg, hit.index, x, y)
    elseif hit.kind == "edge" then
        local _, index = S.segmentById(self.shot, hit.seg.id)
        self:ctxSelect("block", hit.seg)
        self:openTrackMenu(index, x, y)
    elseif hit.kind == "eye" or hit.kind == "tool" or hit.kind == "toolbar" or hit.kind == "top" or hit.kind == "topbar" or hit.kind == "collapse"
        or hit.kind == "playheadMode" or hit.kind == "addActor" then
        return
    elseif hit.kind == "camLabel" then
        self:openCameraMenu(x, y)
    elseif hit.kind == "swatch" then
        self:openPalette(hit.target, x, y)
    elseif hit.kind == "focus" then
        self:ctxSelect("focus", self.shot.focus[hit.index])
        self:openFocusMenu(hit.index, x, y)
    elseif hit.kind == "mark" then
        local seg = self.shot.segments[hit.seg]
        self:ctxSelect("mark", seg.track.marks[hit.index])
        self:openMarkMenu(hit.seg, hit.index, x, y)
    elseif hit.kind == "segment" then
        self:ctxSelect("block", self.shot.segments[hit.index])
        self:openTrackMenu(hit.index, x, y)
    elseif hit.kind == "routePoint" then
        self:openPointMenu(hit.index, hit.point, x, y)
    elseif hit.kind == "chPoint" then
        self:openChannelPointMenu(hit.key, hit.index, x, y)
    elseif hit.kind == "chGraph" or hit.kind == "chList" then
        self:openChannelMenu(hit.key, x, y)
    elseif hit.kind == "chEye" or hit.kind == "chRow" then
        return
    elseif hit.kind == "actorAction" then
        self.activeTarget, self.objectFocus = hit.index, nil
        self:ctxSelect("action", self.shot.actors[hit.index].actions[hit.action])
        self:openActionEditMenu(hit.index, hit.action, x, y)
    elseif hit.kind == "lane" then
        self.activeTarget, self.objectFocus = hit.index, nil
        local actor = self.shot.actors[hit.index]
        local at = math.max(CinemaActions.minTime(actor), math.floor((self:timeAtX(x) - (actor.delay or 0)) * 10 + 0.5) / 10)
        self:openLaneMenu(hit.index, hit.lane, at, x, y)
    elseif hit.focusRow then
        self:openFocusRowMenu(x, y)
    elseif hit.kind == "propsHeader" or hit.kind == "propsCollapse" then
        self:openPropsMenu(x, y)
    elseif hit.kind == "prop" then
        self:openPropMenu(hit.index, x, y)
    elseif hit.kind == "objectsHeader" or hit.kind == "objectsCollapse" then
        self:openObjectsMenu(x, y)
    elseif hit.kind == "object" then
        self:openObjectRowMenu(hit.index, x, y)
    elseif hit.kind == "objAction" then
        self:openObjActionMenu(hit.index, hit.action, x, y)
    elseif hit.kind == "timeline" or hit.kind == "ruler" then
        self:openShotMenu(x, y)
    elseif hit.kind == "actor" then
        self.activeTarget, self.objectFocus = hit.index, nil
        local e = hit.onBlock and self:spanAtScreen(hit.index, x) or nil
        if e ~= nil then
            self:ctxSelect(self:spanObject(hit.index, e))
            self:openSpanMenu(hit.index, e, x, y, self:timeAtX(x))
        else
            self:openActorMenu(hit.index, x, y, nil)
        end
    else
        self:openShotMenu(x, y)
    end
end

-- Pravé tlačítko na věci ji vybere, jen když ještě není ve výběru (menu pak platí pro celý výběr).
function CinemaEditorScreen:ctxSelect(kind, obj)
    if obj ~= nil and not self:selHas(kind, obj) then
        self:selSet(kind, obj)
    end
end

-- Úprava záběru s krokem zpět.
local function edit(self, fn)
    self:pushUndo()
    fn()
    S.touch(self.shot)
    self:syncDrivers()
    self:markDirty()
end

-- Úprava K-framu z menu: s krokem zpět a (mimo pohled shora) kamera skočí na upravenou pózu.
function CinemaEditorScreen:adjustKey(seg, i, fn)
    edit(self, fn)
    if self.topdown == nil then
        self:jumpToKey(seg, i)
    end
end

-- Nabídka K-framu Letu: rychlost kamery v něm, poloha, natočení, ohnisko, smazání.
function CinemaEditorScreen:openKeyMenu(seg, i, x, y)
    local shot = self.shot
    local track = seg ~= nil and seg.track or nil
    local k = track ~= nil and track.keys[i] or nil
    if k == nil then
        return
    end
    local aimed = track.mode ~= S.FLIGHT
    local single = #track.keys < 2
    local free = S.keyIsFree(shot, track, i)
    local fixedSpeed = single or free
    local function speed()
        return (S.keySpeed(shot, track, i))
    end
    local title = string.format(t("cine_menu_keyTitle"), i, seg.t + k.t)
    local function adjust(fn)
        return function(s) s:adjustKey(seg, i, fn) end
    end
    local more = {
        item(string.format(t("cine_menu_keyFocal"), self.targetFocal),
            function(s) s:adjustKey(seg, i, function() k.focal = M.clampFocal(s.targetFocal) end) end),
        stepItem(t("cine_menu_keyUp"), adjust(function() S.nudgeKey(shot, k, 0, 1, 0) end), adjust(function() S.nudgeKey(shot, k, 0, -1, 0) end)),
        stepItem(t("cine_menu_turnLeft"), adjust(function() S.turnKey(shot, k, math.rad(5), 0) end),
            adjust(function() S.turnKey(shot, k, -math.rad(5), 0) end), { disabled = aimed }),
        stepItem(t("cine_menu_lookUp"), adjust(function() S.turnKey(shot, k, 0, -math.rad(5)) end),
            adjust(function() S.turnKey(shot, k, 0, math.rad(5)) end), { disabled = aimed }),
        separator(),
        item(t("cine_menu_keyAuto"), function(s) edit(s, function() S.setKeySpeed(shot, track, i, nil) end) end,
            { keepOpen = true, disabled = fixedSpeed }),
        item(t("cine_menu_keyCurveAuto"), function(s) edit(s, function() k.hin, k.hout = nil, nil end) end,
            { keepOpen = true, disabled = k.hin == nil and k.hout == nil }),
        item(t("cine_menu_constant"), function(s) edit(s, function() S.flightConstantSpeed(shot, track) end) end, { disabled = single }),
    }
    local items = {
        stepItem(function() return string.format(t("cine_menu_keyFaster"), speed()) end,
            function(s) edit(s, function() S.setKeySpeed(shot, track, i, speed() <= 1e-3 and 0.5 or speed() * 1.25) end) end,
            function(s) edit(s, function() S.setKeySpeed(shot, track, i, speed() / 1.25) end) end, { disabled = fixedSpeed }),
        stepItem(function() return string.format(t("cine_menu_keyEase"), t(E.influenceName(k))) end,
            function(s) edit(s, function() S.setKeyInfluence(shot, k, nil, E.nextInfluence(k, 1)) end) end,
            function(s) edit(s, function() S.setKeyInfluence(shot, k, nil, E.nextInfluence(k, -1)) end) end, { disabled = fixedSpeed }),
        separator(),
    }
    for _, pass in ipairs(S.PASSES) do
        items[#items + 1] = item(function()
            return (S.keyPass(k) == pass and "> " or "") .. t("cine_pass_" .. pass) .. " - " .. t("cine_pass_" .. pass .. "_d")
        end, function(s) edit(s, function() S.setKeyPass(shot, k, pass) end) end, { keepOpen = true, disabled = single })
    end
    items[#items + 1] = item(function() return (k.free and "> " or "") .. t("cine_menu_keyFree") end,
        function(s) edit(s, function() S.setKeyFree(shot, k, not k.free) end) end,
        { keepOpen = true, disabled = single or i == 1 or i == #track.keys })
    for _, entry in ipairs({
        separator(),
        groupItem(t("cine_menu_more"), title, more, x, y),
        separator(),
        item(t("cine_menu_deleteKey"), function(s)
            s:setSelectedKey(seg, i)
            s:onActionKeyDelete()
        end),
    }) do
        items[#items + 1] = entry
    end
    self:openMenu(title, items, x, y)
end

-- Délka rozjezdu a dojezdu K-framu: krátký → střední → dlouhý (podle průměru obou stran).
E.INFLUENCE_ORDER = { "short", "medium", "long" }

function E.influenceName(key)
    local v = (S.influence(key, "in") + S.influence(key, "out")) * 0.5
    local best, bestDist = "medium", math.huge
    for _, name in ipairs(E.INFLUENCE_ORDER) do
        local d = math.abs(S.INFLUENCE_PRESETS[name] - v)
        if d < bestDist then
            best, bestDist = name, d
        end
    end
    return "cine_ease_" .. best
end

function E.nextInfluence(key, dir)
    local current = E.influenceName(key):sub(#"cine_ease_" + 1)
    local n = #E.INFLUENCE_ORDER
    for i, name in ipairs(E.INFLUENCE_ORDER) do
        if name == current then
            local nextName = E.INFLUENCE_ORDER[(i - 1 + (dir or 1)) % n + 1]
            return nextName ~= "medium" and S.INFLUENCE_PRESETS[nextName] or nil
        end
    end
    return nil
end

-- Úsek Letu mezi dvěma K-framy v čase rel (s od začátku bloku): přímka, oblouk, z bodu do bodu, stálou rychlostí.
local function spanItems(self, seg, rel)
    local shot, track = self.shot, seg.track
    local i = S.flightSpanAt(track, rel)
    if i == nil then
        return nil
    end
    local items = {}
    for _, shape in ipairs({ "straight", "curve", "stops", "constant" }) do
        items[#items + 1] = item(function()
            local mark = ""
            if shape == "straight" and S.spanIsStraight(track, i) or shape == "curve" and not S.spanIsStraight(track, i) then
                mark = "> "
            end
            return mark .. t("cine_span_" .. shape)
        end, function(s) edit(s, function() S.setSpanShape(shot, track, i, shape) end) end, { keepOpen = true })
    end
    return items, string.format(t("cine_span_title"), i, i + 1)
end
E.spanItems = spanItems

-- Kamery záběru: přepnutí na jinou, nová prázdná a smazání té vybrané.
function CinemaEditorScreen:openCameraMenu(x, y)
    local shot = self.shot
    local items = {}
    for i = 1, #shot.cameras do
        items[#items + 1] = item(function()
            return string.format(t(i == shot.camIndex and "cine_menu_cameraCurrent" or "cine_menu_cameraSwitch"), i)
        end, function(s) s:selectCamera(i) end)
    end
    items[#items + 1] = item(t("cine_menu_cameraNew"), function(s) s:addCamera() end)
    items[#items + 1] = item(t("cine_menu_cameraDelete"), function(s) s:removeCamera() end, { disabled = #shot.cameras < 2 })
    self:openMenu(t("cine_menu_cameraTitle"), items, x, y)
end

E.SHAKE_LEVELS = { "cine_shake_0", "cine_shake_1", "cine_shake_2", "cine_shake_3" }

-- Jedna položka prostředí záběru (nil = beze změny); s krokem zpět, prázdné nastavení se zahodí.
local function setEnv(self, field, value)
    edit(self, function()
        local shot = self.shot
        shot.env = shot.env or {}
        shot.env[field] = value
        if next(shot.env) == nil then
            shot.env = nil
        end
    end)
    self:applyEnvironment()
end

local function envHour(self)
    local env = self.shot.env
    return env ~= nil and env.hour or Env.hour() or 12
end

local function envWeatherText(self)
    local env = self.shot.env
    return env ~= nil and env.weather ~= nil and Env.weatherText(env.weather) or t("cine_env_unchanged")
end

function CinemaEditorScreen:openWeatherMenu(x, y)
    local items = {}
    for _, name in ipairs(Env.weatherNames()) do
        items[#items + 1] = item(function()
            local env = self.shot.env
            return (env ~= nil and env.weather == name and "> " or "") .. Env.weatherText(name)
        end, function(s) setEnv(s, "weather", name) end, { keepOpen = true })
    end
    items[#items + 1] = item(t("cine_menu_envWeatherClear"), function(s) setEnv(s, "weather", nil) end, { keepOpen = true })
    self:openMenu(t("cine_menu_envWeatherTitle"), items, x, y)
end

-- Čas, roční období a počasí záběru; změna se projeví hned a ukládá se do záběru.
function CinemaEditorScreen:openEnvironmentMenu(x, y)
    local function hourItem(textKey, delta)
        return stepItem(function() return string.format(t(textKey), Env.formatHour(envHour(self))) end,
            function(s) setEnv(s, "hour", Env.stepHour(envHour(s), delta)) end,
            function(s) setEnv(s, "hour", Env.stepHour(envHour(s), -delta)) end)
    end
    local items = {
        hourItem("cine_menu_envHourUp", 1),
        hourItem("cine_menu_envHourUpFine", Env.HOUR_STEP),
        item(t("cine_menu_envHourClear"), function(s) setEnv(s, "hour", nil) end, { keepOpen = true }),
        separator(),
    }
    for _, key in ipairs(Env.SEASONS) do
        items[#items + 1] = item(function()
            local env = self.shot.env
            return string.format(t("cine_menu_envSeason"), (env ~= nil and env.season == key and "> " or "") .. t("cine_season_" .. key))
        end, function(s) setEnv(s, "season", key) end, { keepOpen = true })
    end
    items[#items + 1] = item(t("cine_menu_envSeasonClear"), function(s) setEnv(s, "season", nil) end, { keepOpen = true })
    items[#items + 1] = separator()
    items[#items + 1] = item(function() return string.format(t("cine_menu_envWeather"), envWeatherText(self)) end,
        function(s) s:openWeatherMenu(x, y) end, { submenu = true })
    items[#items + 1] = separator()
    items[#items + 1] = item(t("cine_menu_envClear"), function(s)
        edit(s, function() s.shot.env = nil end)
        s:applyEnvironment()
    end, { keepOpen = true, disabled = self.shot.env == nil })
    self:openMenu(t("cine_menu_envTitle"), items, x, y)
end

function CinemaEditorScreen:openShotMenu(x, y, title)
    local shot = self.shot
    title = title or shot.name
    local settings = {
        E.dockItem(),
        item(function() return string.format(t("cine_menu_speedStep"), E.speedStepOf()) end,
            function(s) s:cycleSpeedStep() end, { keepOpen = true }),
        stepItem(function() return string.format(t("cine_menu_preroll"), shot.preroll) end,
            function(s) edit(s, function() shot.preroll = (math.floor(shot.preroll + 0.5) + 1) % 4 end) end,
            function(s) edit(s, function() shot.preroll = (math.floor(shot.preroll + 0.5) - 1) % 4 end) end),
        stepItem(function() return string.format(t("cine_menu_shake"), t(E.SHAKE_LEVELS[(shot.shake or 0) + 1])) end,
            function(s) edit(s, function() shot.shake = ((shot.shake or 0) + 1) % 4 end) end,
            function(s) edit(s, function() shot.shake = ((shot.shake or 0) - 1) % 4 end) end),
        item(function()
            if (shot.bank or 0) > 0 then
                return string.format(t("cine_menu_bankOn"), shot.bank)
            end
            return t("cine_menu_bankOff")
        end, function(s)
            edit(s, function()
                local steps = E.BANK_STEPS
                local index = 1
                for i, value in ipairs(steps) do
                    if value == (shot.bank or 0) then
                        index = i
                    end
                end
                shot.bank = steps[index % #steps + 1]
            end)
        end, { keepOpen = true }),
    }
    if #shot.focus > 0 then
        settings[#settings + 1] = item(t("cine_menu_focusFree"), function(s) s:setFocusHere(nil) end)
        settings[#settings + 1] = item(t("cine_menu_focusClear"), function(s) edit(s, function() shot.focus = {} end) end)
    end
    local shots = {
        item(t("cine_menu_playFromHere"), function(s) s:playAllShots(s.index.active) end,
            { disabled = self.index.active >= #self.index.files }),
        item(t("cine_menu_playAll"), function(s) s:playAllShots() end, { disabled = #self.index.files < 2 }),
        separator(),
        stepItem(t("cine_menu_shotNext"), function(s) s:switchShot(1) end, function(s) s:switchShot(-1) end,
            { disabled = #self.index.files < 2 }),
        item(t("cine_menu_shotNew"), function(s) s:newShot() end),
        separator(),
        item(t("cine_menu_shotDelete"), function(s) s:deleteShot() end, { disabled = #self.index.files < 2 }),
    }
    local bounds = {
        item(string.format(t("cine_menu_endHere"), self.playhead), function(s)
            edit(s, function() shot.endMark = s.playhead end)
        end, { disabled = self.playhead < 0.1 }),
        item(function() return string.format(t("cine_menu_endClear"), shot.endMark or 0) end,
            function(s) edit(s, function() shot.endMark = nil end) end, { disabled = shot.endMark == nil }),
    }
    local items = {
        item(t("cine_menu_addAction"), function(s) s:openAddPanel() end, { submenu = true }),
        item(function() return string.format(t("cine_menu_paste"), E.clipboard ~= nil and #E.clipboard.items or 0) end,
            function(s) s:pasteClipboard() end, { disabled = E.clipboard == nil }),
        item(function() return string.format(t("cine_menu_camera"), shot.camIndex, #shot.cameras) end,
            function(s) s:openCameraMenu(x, y) end, { submenu = true }),
        item(function()
            local summary = Env.summary(shot.env)
            return string.format(t("cine_menu_env"), summary ~= "" and summary or t("cine_env_unchanged"))
        end, function(s) s:openEnvironmentMenu(x, y) end, { submenu = true, disabled = not Env.available() }),
        groupItem(t("cine_menu_bounds"), title, bounds, x, y),
        separator(),
        groupItem(t("cine_menu_shots"), title, shots, x, y),
        groupItem(t("cine_menu_shotSettings"), title, settings, x, y),
        separator(),
        item(t("cine_menu_clearKeys"), function(s)
            edit(s, function()
                while #shot.segments > 0 do
                    S.removeSegment(shot, 1)
                end
            end)
            s:selClear()
            s.playhead = 0
        end, { disabled = #shot.segments == 0 }),
    }
    self:openMenu(title, items, x, y)
end

E.MODES_WITH_DIR = { orbit = true, helix = true, boomerang = true }
-- Režimy, ve kterých jde zapnout automatický zoom (cíl drží velikost); sledování z bodu ho má vlastní.
E.AUTO_ZOOM_MODES = { orbit = true, dronie = true, rocket = true, helix = true, approach = true, follow = true, boomerang = true,
    pass = true, parallel = true, topdown = true, pair = true }

-- Další (dir 1) nebo předchozí hodnota ze seznamu, dokola.
function E.nextOf(list, value, dir)
    for k, v in ipairs(list) do
        if v == value then
            return list[(k - 1 + dir) % #list + 1]
        end
    end
    return list[1]
end

-- Třes bloku: nil = jako záběr, pak úrovně 0–3 (0 = bez třesu i v záběru s třesem).
function E.nextShake(shake, dir)
    local index = (shake == nil and 0 or shake + 1) + dir
    index = index % (#E.SHAKE_LEVELS + 1)
    if index == 0 then
        return nil
    end
    return index - 1
end

-- Čas (s od začátku záběru), kam padne nový K-frame v bloku: playhead, je-li v bloku, jinak střed.
local function markTime(self, seg)
    local d = seg.track.duration or 1
    if self.playhead > seg.t and self.playhead < seg.t + d then
        return self.playhead
    end
    return seg.t + d * 0.5
end

-- Menu K-framu uvnitř režimu: zoom, rychlost pohybu po dráze režimu, smazání.
function CinemaEditorScreen:openMarkMenu(segIndex, i, x, y)
    local seg = self.shot.segments[segIndex]
    local mark = seg ~= nil and seg.track.marks ~= nil and seg.track.marks[i] or nil
    if mark == nil then
        return
    end
    local track = seg.track
    local moving = Mo.MOVING[track.mode] == true
    local items = {
        stepItem(function() return string.format(t("cine_menu_markFaster"), mark.speed or 1) end,
            function(s) edit(s, function() Mo.adjustMark(track, i, "speed", 1) end) end,
            function(s) edit(s, function() Mo.adjustMark(track, i, "speed", -1) end) end, { disabled = not moving }),
        stepItem(function() return string.format(t("cine_menu_markZoomUp"), mark.focal or 35) end,
            function(s) edit(s, function() Mo.adjustMark(track, i, "focal", 1) end) end,
            function(s) edit(s, function() Mo.adjustMark(track, i, "focal", -1) end) end, { disabled = track.autoZoom == true }),
        separator(),
        item(t("cine_menu_markDelete"), function(s)
            s:selClear()
            edit(s, function() Mo.removeMark(track, i) end)
        end),
    }
    self:openMenu(string.format(t("cine_menu_markTitle"), seg.t + mark.u * (track.duration or 1)), items, x, y)
end

-- Změna parametru režimu; prodloužení bloku přes jiný blok se vrátí.
local function adjustTrack(self, seg, key, steps)
    local track = seg.track
    local old = track[key]
    Mo.adjust(track, key, steps)
    if key == "duration" and S.segmentOverlaps(self.shot, seg) then
        track[key] = old
        self:showMessage(t("cine_msg_segmentBusy"))
    end
end

-- Menu Stav (lišta osy): jen ke čtení, co dřív ukazovaly řádky nad osou.
function CinemaEditorScreen:openInfoMenu(x, y)
    local items = {}
    for _, line in ipairs(self:statusLines()) do
        if #items < 10 then
            items[#items + 1] = item(line, function() end, { disabled = true })
        end
    end
    self:openMenu(t("cine_tb_info"), items, x, y)
end

-- Nastavení bloku: parametry jeho druhu, K-framy, plynulé navázání na předchozí blok a úpravy na ose.
function CinemaEditorScreen:openTrackMenu(index, x, y)
    local shot = self.shot
    local seg = shot.segments[index]
    if seg == nil then
        return
    end
    local track = seg.track
    local keyed = S.hasKeys(track)
    local title = E.trackLabel(track)
    if track.target ~= nil then
        title = string.format("%s – %s", title, self:targetName(track.target) or "?")
    end
    local items, more, params = {}, {}, {}
    if keyed and #track.keys >= 2 then
        local rel = self:timeAtX(x) - seg.t
        if rel < 0 or rel > (track.duration or 0) then
            rel = self.playhead - seg.t
        end
        local span, spanTitle = spanItems(self, seg, rel)
        if span ~= nil then
            items[#items + 1] = groupItem(spanTitle, spanTitle, span, x, y)
        end
        local profiles = {}
        for _, profile in ipairs({ "uniform", "constant", "easeInOut", "accelerate", "decelerate" }) do
            profiles[#profiles + 1] = item(t("cine_profile_" .. profile),
                function(s) edit(s, function() S.setFlightProfile(shot, track, profile) end) end, { keepOpen = true })
        end
        for _, side in ipairs({ "in", "out" }) do
            local field = side == "in" and "rampIn" or "rampOut"
            profiles[#profiles + 1] = stepItem(function() return string.format(t("cine_profile_ramp_" .. side), track[field] or 0) end,
                function(s) edit(s, function() S.setFlightRamp(shot, track, side, (track[field] or 0) + S.RAMP_STEP) end) end,
                function(s) edit(s, function() S.setFlightRamp(shot, track, side, (track[field] or 0) - S.RAMP_STEP) end) end)
        end
        items[#items + 1] = groupItem(t("cine_menu_profile"), title, profiles, x, y)
    end
    if keyed then
        table.insert(items, 1, stepItem(function() return string.format(t("cine_menu_blockFaster"), track.duration) end,
            function(s) edit(s, function() S.scaleSegment(shot, seg, 1.25) end) end,
            function(s) edit(s, function() S.scaleSegment(shot, seg, 1 / 1.25) end) end))
        more[#more + 1] = item(function() return string.format(t("cine_menu_flightAverage"), S.flightAverage(shot, track)) end,
            function(s) edit(s, function() S.flightConstantSpeed(shot, track) end) end, { disabled = #track.keys < 2 })
    end
    for _, a in ipairs(Mo.ADJUSTABLE[track.mode] or {}) do
        local key = a[1]
        local label = t("cine_param_" .. key)
        local scale = Mo.DISPLAY_SCALE[key] or 1
        params[#params + 1] = stepItem(function() return string.format("%s: %.1f", label, (Mo.value(track, key) or 0) * scale) end,
            function(s) edit(s, function() adjustTrack(s, seg, key, 1) end) end,
            function(s) edit(s, function() adjustTrack(s, seg, key, -1) end) end)
    end
    if E.MODES_WITH_DIR[track.mode] then
        params[#params + 1] = item(function() return t((track.dir or 1) > 0 and "cine_menu_dirCw" or "cine_menu_dirCcw") end,
            function(s) edit(s, function() track.dir = -(track.dir or 1) end) end, { keepOpen = true })
    end
    if track.mode == "spotlight" then
        params[#params + 1] = item(function() return t(track.autoZoom and "cine_menu_autoZoomOn" or "cine_menu_autoZoomOff") end,
            function(s) edit(s, function() track.autoZoom = not track.autoZoom end) end, { keepOpen = true })
    elseif E.AUTO_ZOOM_MODES[track.mode] then
        -- velikost cíle v obraze se drží tak, jak je na začátku bloku
        params[#params + 1] = item(function() return t(track.autoZoom and "cine_menu_autoZoomOn" or "cine_menu_autoZoomOff") end,
            function(s) edit(s, function()
                track.autoZoom = not track.autoZoom
                if track.autoZoom then
                    track.dist0 = s:blockTargetDistance(seg, seg.t) or track.dist0 or 20
                end
            end) end, { keepOpen = true })
    end
    if track.mode == "topdown" then
        params[#params + 1] = item(function() return t(track.rotate and "cine_menu_topRotateOn" or "cine_menu_topRotateOff") end,
            function(s) edit(s, function() track.rotate = not track.rotate end) end, { keepOpen = true })
    end
    if track.mode == "pov" then
        params[#params + 1] = stepItem(function() return string.format(t("cine_menu_povVariant"), t("cine_pov_" .. (track.variant or "eyes"))) end,
            function(s) edit(s, function() track.variant = E.nextOf(Mo.POV_VARIANTS, track.variant or "eyes", 1) end) end,
            function(s) edit(s, function() track.variant = E.nextOf(Mo.POV_VARIANTS, track.variant or "eyes", -1) end) end)
    end
    params[#params + 1] = stepItem(function()
        return string.format(t("cine_menu_blockShake"), track.shake ~= nil and t(E.SHAKE_LEVELS[track.shake + 1]) or t("cine_shake_shot"))
    end, function(s) edit(s, function() track.shake = E.nextShake(track.shake, 1) end) end,
        function(s) edit(s, function() track.shake = E.nextShake(track.shake, -1) end) end)
    if #params > 0 then
        table.insert(items, 1, groupItem(t("cine_menu_modeParams"), title, params, x, y))
    end
    -- připevnění drží souřadnice části vozidla a pohled postavy jen postavu: cíl se u nich nemění
    if track.target ~= nil and track.mode ~= "mount" and track.mode ~= "pov" then
        table.insert(items, 1, item(string.format(t("cine_menu_blockTarget"), self:targetName(track.target) or "?"),
            function(s) s:openRetargetMenu(seg, x, y) end, { submenu = true }))
    end
    items[#items + 1] = separator()
    items[#items + 1] = item(t("cine_menu_blockSplit"), function(s) s:splitBlock(seg) end, { disabled = not self:canSplit(seg, self.playhead) })
    items[#items + 1] = item(t("cine_menu_blockDuplicate"), function(s) s:duplicateSelection() end)
    items[#items + 1] = item(function() return t(track.smooth and "cine_menu_smoothOn" or "cine_menu_smoothOff") end,
        function(s) edit(s, function() track.smooth = not track.smooth or nil end) end, { keepOpen = true })
    if track.smooth then
        more[#more + 1] = stepItem(function() return string.format(t("cine_menu_smoothLonger"), track.blend or S.SMOOTH_BLEND) end,
            function(s) edit(s, function() track.blend = (track.blend or S.SMOOTH_BLEND) + 0.5 end) end,
            function(s) edit(s, function() track.blend = math.max((track.blend or S.SMOOTH_BLEND) - 0.5, 0.5) end) end)
    end
    if Mo.STANDS[track.mode] then
        more[#more + 1] = item(t("cine_menu_spotHere"), function(s)
            local cam = s.cam
            edit(s, function()
                track.camX, track.camY, track.camZ, track.yaw, track.pitch = cam.x, cam.y, cam.z, cam.yaw, cam.pitch
            end)
        end)
        more[#more + 1] = stepItem(t("cine_menu_spotUp"),
            function(s) edit(s, function() track.camY = track.camY + E.NUDGE_STEP * E.stepFactor() end) end,
            function(s) edit(s, function() track.camY = track.camY - E.NUDGE_STEP * E.stepFactor() end) end)
    end
    more[#more + 1] = item(function() return string.format(t("cine_menu_markAdd"), markTime(self, seg)) end, function(s)
        if keyed then
            s:insertCamKeyAt(markTime(s, seg))
        else
            s:addModeMark(seg)
        end
    end)
    if track.marks ~= nil then
        more[#more + 1] = item(t("cine_menu_markClear"), function(s) edit(s, function() track.marks = nil end) end)
    end
    if not keyed then
        more[#more + 1] = item(t("cine_menu_trackRestart"), function(s) s:restartTrackHere(seg) end)
    end
    if track.shiftX ~= nil or track.aimYaw ~= nil then
        more[#more + 1] = item(t("cine_menu_shiftClear"), function(s) edit(s, function() Mo.clearShift(track) end) end)
    end
    more[#more + 1] = item(t("cine_menu_blockReplace"), function(s) s:openReplaceMenu(seg, x, y) end, { submenu = true, disabled = track.mode == S.FLIGHT })
    more[#more + 1] = item(t("cine_menu_copy"), function(s) s:copySelection() end)
    more[#more + 1] = item(t("cine_menu_blockRipple"), function(s) s:deleteSelection(true) end)
    items[#items + 1] = separator()
    items[#items + 1] = groupItem(t("cine_menu_more"), title, more, x, y)
    items[#items + 1] = separator()
    items[#items + 1] = item(t("cine_menu_trackOff"), function(s) edit(s, function() S.removeSegment(shot, index) end) end)
    self:openMenu(title, items, x, y)
end

-- Režim bloku se vymění za jiný (čas, délka, ohnisko a značky zůstanou).
function CinemaEditorScreen:openReplaceMenu(seg, x, y)
    local items = {}
    local modes = {}
    for _, mode in ipairs(Mo.ORDER) do
        modes[#modes + 1] = mode
    end
    modes[#modes + 1] = "static"
    for _, mode in ipairs(modes) do
        items[#items + 1] = item(function() return (seg.track.mode == mode and "> " or "") .. t("cine_mode_" .. mode) end,
            function(s) s:replaceBlockMode(seg, mode) end)
    end
    self:openMenu(t("cine_menu_blockReplace"), items, x, y)
end

-- Menu bodu trasy vozidla: rychlost v bodě (mezi body se mění plynule), smazání.
function CinemaEditorScreen:openPointMenu(actorIndex, pointIndex, x, y)
    local actor = self.shot.actors[actorIndex]
    local p = actor ~= nil and actor.points[pointIndex] or nil
    if p == nil then
        return
    end
    local function kmh()
        return p[3] or actor.speed or E.ACTOR_SPEED_DEFAULT
    end
    local function change(s, fn)
        edit(s, function() s:keepOnRoute(actor, fn) end)
        s.actorRt = {}
    end
    -- rychlost tohoto bodu i všech následujících (nil = zpět na rychlost trasy)
    local function setFrom(kmhValue)
        for j = pointIndex, #actor.points do
            actor.points[j][3] = kmhValue
        end
    end
    local person = CinemaPerson.isPerson(actor)
    -- s křivkou rychlosti v panelu V se rychlost a pauzy řídí jí, ne body trasy
    local curved = not person and CinemaChannels.hasPoints(actor.curves ~= nil and actor.curves.speed or nil)
    -- s křivkou se zastavuje v ní (Zastavit tady v grafu rychlosti), pauza bodu by se ignorovala
    local wait = stepItem(function() return string.format(t("cine_menu_pointWaitUp"), p[4] or 0) end,
        function(s) change(s, function() s:setPointWait(actorIndex, pointIndex, (p[4] or 0) + 1) end) end,
        function(s) change(s, function() s:setPointWait(actorIndex, pointIndex, (p[4] or 0) > 1 and p[4] - 1 or nil) end) end,
        { disabled = curved or pointIndex == 1 or pointIndex == #actor.points })
    local items
    if person then
        -- postava jde pomalu, jde, nebo běží vždy od bodu do dalšího, stojí pauzou v bodě; necouvá
        items = E.walkItems(actor, pointIndex, change)
        items[#items + 1] = wait
    else
        items = {
            stepItem(function() return string.format(t("cine_menu_pointFaster"), E.speedStepOf(), kmh()) end,
                function(s) change(s, function() p[3] = math.min(kmh() + s.speedStep, 80) end) end,
                function(s) change(s, function() p[3] = math.max(kmh() - s.speedStep, 0) end) end, { disabled = curved }),
            stepItem(function() return string.format(t("cine_menu_fromFaster"), E.speedStepOf(), kmh()) end,
                function(s) change(s, function() setFrom(math.min(kmh() + s.speedStep, 80)) end) end,
                function(s) change(s, function() setFrom(math.max(kmh() - s.speedStep, 0)) end) end, { disabled = curved }),
            wait,
            item(function() return t(p[5] and "cine_menu_pointForward" or "cine_menu_pointReverse") end, function(s)
                local start = actor.start ~= nil and actor.start.entries[1] or nil
                if not p[5] and not W.canReverse(start ~= nil and W.find(start.uid) or nil) then
                    s:showMessage(t("cine_msg_cannotReverse"))
                    return
                end
                change(s, function() p[5] = (not p[5]) or nil end)
            end, { keepOpen = true, disabled = pointIndex == 1 }),
        }
    end
    items[#items + 1] = item(t("cine_menu_pointAction"), function(s)
        local at = math.max((s:routePointTime(actorIndex, pointIndex) or (actor.delay or 0)) - (actor.delay or 0), 0)
        if person then
            s:openPersonActionMenu(actorIndex, at, x, y)
        else
            s:openVehicleActionMenu(actorIndex, at, x, y)
        end
    end, { submenu = true })
    if not person then
        items[#items + 1] = separator()
        items[#items + 1] = item(t("cine_menu_pointDefault"), function(s) change(s, function() p[3] = nil end) end, { disabled = curved })
        items[#items + 1] = item(t("cine_menu_fromDefault"), function(s) change(s, function() setFrom(nil) end) end, { disabled = curved })
    end
    if curved then
        items[#items + 1] = item(t("cine_ch_clearSpeed"), function(s)
            s:clearChannel({ owner = actorIndex, id = "speed", kind = "speed", key = string.format("a%d:speed", actorIndex) })
        end)
    end
    if person then
        items[#items + 1] = separator()
        -- bod výstupu stojí u vozidla; posunout ho jde, až když to uživatel povolí (od dveří k němu postava dojde)
        if p[7] then
            if p[8] then
                items[#items + 1] = item(t("cine_menu_exitAuto"), function(s) change(s, function() p[8] = nil end) end)
            else
                items[#items + 1] = item(t("cine_menu_exitManual"), function(s)
                    change(s, function() p[8] = true end)
                    s:showMessage(t("cine_msg_exitManual"))
                end)
            end
        end
        local function walkHeading()
            return CinemaPerson.walkHeading(actor, pointIndex)
        end
        local function turn(s, delta)
            change(s, function() p[6] = (p[6] or walkHeading()) + delta end)
        end
        local function angle()
            return math.deg(M.angleDiff(walkHeading(), p[6] or walkHeading()))
        end
        -- bez zadání se postava dívá po směru cesty; natočení (a šipka shora) jen na vyžádání
        if p[6] == nil then
            items[#items + 1] = item(t("cine_menu_faceSet"), function(s)
                change(s, function() p[6] = walkHeading() end)
                s:showMessage(t("cine_msg_faceSet"))
            end)
        else
            items[#items + 1] = stepItem(function() return string.format(t("cine_menu_faceLeft"), angle()) end,
                function(s) turn(s, math.rad(45)) end, function(s) turn(s, -math.rad(45)) end)
            items[#items + 1] = item(t("cine_menu_faceWalk"), function(s) change(s, function() p[6] = nil end) end)
        end
    end
    items[#items + 1] = separator()
    items[#items + 1] = item(t("cine_menu_pointDelete"), function(s) s:deleteRoutePoint({ actor = actorIndex, index = pointIndex }) end,
        { disabled = pointIndex == 1 or (p[7] and CinemaPerson.isOrphanExit(actor, pointIndex) == false) })
    self.activeTarget = actorIndex
    self:openMenu(string.format(t("cine_menu_pointTitle"), pointIndex, actor.name or "?"), items, x, y)
end

-- Menu bodu zájmu na ose: smazat, doba přechodu, výška cíle, volný pohled.
function CinemaEditorScreen:openFocusMenu(i, x, y)
    local shot = self.shot
    local f = shot.focus[i]
    if f == nil then
        return
    end
    local function change(s, fn)
        edit(s, fn)
    end
    local function pick(s, from)
        s.pendingAction = { focusTarget = f, from = from }
        s.picking = true
        s:needCursor()
        s:showMessage(t("cine_msg_pickFocus"))
    end
    local nextF = shot.focus[i + 1]
    local inside = self.playhead - f.t >= S.MIN_GAP and (nextF == nil or nextF.t - self.playhead >= S.MIN_GAP)
    local title = string.format(t("cine_menu_focusTitle"), f.t, self:targetName(f.target) or t("cine_focus_free"))
    local targets = {}
    for _, c in ipairs(self:focusCandidates()) do
        targets[#targets + 1] = item((c.target == f.target and "> " or "") .. c.label,
            function(s) s:changeFocusTarget(f, nil, nil, c.target) end)
    end
    local framing = {}
    for _, preset in ipairs(E.FRAMING_PRESETS) do
        framing[#framing + 1] = item(function()
            local on = math.abs((f.ox or 0) - preset[2]) < 1e-3 and math.abs((f.oy or 0) - preset[3]) < 1e-3
            return (on and "> " or "") .. t(preset[1])
        end, function(s) change(s, function() f.ox, f.oy = preset[2] ~= 0 and preset[2] or nil, preset[3] ~= 0 and preset[3] or nil end) end,
            { keepOpen = true })
    end
    local function nudge(dx, dy)
        return function(s) change(s, function()
            f.ox = M.clamp((f.ox or 0) + dx, -1, 1)
            f.oy = M.clamp((f.oy or 0) + dy, -1, 1)
        end) end
    end
    framing[#framing + 1] = separator()
    framing[#framing + 1] = stepItem(function() return string.format(t("cine_menu_frameRight"), f.ox or 0, f.oy or 0) end,
        nudge(0.05, 0), nudge(-0.05, 0))
    framing[#framing + 1] = stepItem(function() return string.format(t("cine_menu_frameUp"), f.ox or 0, f.oy or 0) end,
        nudge(0, 0.05), nudge(0, -0.05))
    local onPoint = S.pointOfTarget(self.shot, f.target) ~= nil
    local items = {
        groupItem(t("cine_menu_focusList"), title, targets, x, y),
        item(t("cine_menu_focusChange"), function(s) pick(s, nil) end),
        groupItem(string.format(t("cine_menu_framing"), f.ox or 0, f.oy or 0), title, framing, x, y),
        stepItem(function() return string.format(t("cine_menu_blendUp"), f.blend or S.FOCUS_BLEND) end,
            function(s) change(s, function() f.blend = (f.blend or S.FOCUS_BLEND) + 0.5 end) end,
            function(s) change(s, function() f.blend = math.max((f.blend or S.FOCUS_BLEND) - 0.5, 0) end) end),
        stepItem(function()
                local height = f.height or S.FOCUS_HEIGHT
                return string.format(t("cine_menu_focusHigher"), onPoint and height - S.FOCUS_HEIGHT or height)
            end,
            function(s) change(s, function() f.height = (f.height or S.FOCUS_HEIGHT) + 0.5 end) end,
            function(s) change(s, function() f.height = (f.height or S.FOCUS_HEIGHT) - 0.5 end) end,
            { disabled = f.target == nil }),
        separator(),
        item(string.format(t("cine_menu_focusFrom"), self.playhead), function(s) pick(s, s.playhead) end, { disabled = not inside }),
        item(string.format(t("cine_menu_focusSplit"), self.playhead), function(s) s:splitFocusHere(nil) end, { disabled = not inside }),
        item(string.format(t("cine_menu_focusCut"), self.playhead), function(s) s:splitFocusHere(false) end,
            { disabled = not inside or f.target == nil }),
        item(t("cine_menu_focusFreeHere"), function(s) change(s, function() f.target = nil end) end, { disabled = f.target == nil }),
        separator(),
        item(t("cine_menu_focusDelete"), function(s)
            change(s, function() S.removeFocus(shot, i) end)
            s:selClear()
        end),
    }
    self:openMenu(title, items, x, y)
end

-- Prázdné místo řádku bodů zájmu: nový bod na ukazateli (cíl ze seznamu, ze scény, volný pohled), skrytí prázdného řádku.
function CinemaEditorScreen:openFocusRowMenu(x, y)
    local shot = self.shot
    local title = string.format(t("cine_menu_focusRowTitle"), self.playhead)
    local items = {}
    for _, c in ipairs(self:focusCandidates()) do
        items[#items + 1] = item(c.label, function(s) s:addFocusTarget(c.target) end)
    end
    if #items > 0 then
        items[#items + 1] = separator()
    end
    items[#items + 1] = item(t("cine_menu_focusPick"), function(s)
        s.pendingAction = { focus = true }
        s.picking = true
        s:needCursor()
        s:showMessage(t("cine_msg_pickFocus"))
    end)
    items[#items + 1] = item(t("cine_menu_focusAddFree"), function(s) s:addFocusTarget(nil) end, { disabled = #shot.focus == 0 })
    items[#items + 1] = item(t("cine_menu_focusRowHide"), function(s) edit(s, function() shot.focusRow = nil end) end,
        { disabled = #shot.focus > 0 })
    self:openMenu(title, items, x, y)
end

-- Místo cíle v obraze: { text, x, y } (0 = střed, ±1 = kraj, třetiny podle pravidla třetin).
E.FRAMING_PRESETS = {
    { "cine_frame_center", 0, 0 }, { "cine_frame_left", -1 / 3, 0 }, { "cine_frame_right", 1 / 3, 0 },
    { "cine_frame_top", 0, 1 / 3 }, { "cine_frame_bottom", 0, -1 / 3 },
}

-- Další řidič v pořadí: žádný, pomocníci podle HelperManageru, zase žádný (dir -1 obráceně).
function E.nextDriver(current, dir)
    local names = { false }
    for _, helper in ipairs(W.helperList()) do
        names[#names + 1] = helper.name
    end
    local index = 1
    for i, name in ipairs(names) do
        if name == current then
            index = i
        end
    end
    return names[(index - 1 + (dir or 1)) % #names + 1] or nil
end

local function s_detailIs(self, i)
    return self:getDetail() == i
end

-- Index úseku trasy vozidla i (mezi body j a j + 1), nad kterým je kurzor; nil mimo úseky nebo v pauze.
function CinemaEditorScreen:routeSpanAtScreen(i, x)
    return self:routeSpanAtTime(i, self:timeAtX(x))
end

function CinemaEditorScreen:routeSpanAtTime(i, t)
    local a = self.shot.actors[i]
    for j = 1, #(a.points or {}) - 1 do
        -- (před bodem výstupu postava sedí ve vozidle, to úsek trasy není)
        local from, to = self:routePointTime(i, j), not a.points[j + 1][7] and self:routePointTime(i, j + 1) or nil
        if from ~= nil and to ~= nil and t >= from + (a.points[j][4] or 0) and t < to then
            return j
        end
    end
    return nil
end

-- Rychlost úseku postavy od bodu j: předvolby chůze, jemné ladění o krok rychlosti a stejná rychlost až do konce trasy.
function E.walkItems(actor, j, change)
    local p = actor.points[j]
    return {
        E.gaitItem(actor, j, change),
        stepItem(function() return string.format(t("cine_menu_walkSpeed"), j + 1, E.speedStepOf(), CinemaPerson.speedOf(p)) end,
            function(s) change(s, function() CinemaPerson.setSpeed(p, CinemaPerson.speedOf(p) + s.speedStep) end) end,
            function(s) change(s, function() CinemaPerson.setSpeed(p, CinemaPerson.speedOf(p) - s.speedStep) end) end,
            { disabled = j >= #actor.points }),
        item(string.format(t("cine_menu_walkFrom"), j + 1), function(s) change(s, function() CinemaPerson.speedFrom(actor, j) end) end,
            { disabled = j >= #actor.points - 1 }),
    }
end

-- Chůze postavy v úseku od bodu j do dalšího: klik další, pravé tlačítko předchozí.
function E.gaitItem(actor, j, change)
    local p = actor.points[j]
    return stepItem(function() return string.format(t("cine_menu_gait"), j + 1, CinemaPerson.gaitTitle(p[3])) end,
        function(s) change(s, function() CinemaPerson.stepGait(p, 1) end) end,
        function(s) change(s, function() CinemaPerson.stepGait(p, -1) end) end, { disabled = j >= #actor.points })
end

-- Položky úseku trasy mezi body j a j + 1: rychlost obou krajních bodů najednou (postava: chůze úseku).
local function routeSpanItems(self, i, j)
    local actor = self.shot.actors[i]
    local p1, p2 = actor.points[j], actor.points[j + 1]
    if p1 == nil or p2 == nil then
        return {}
    end
    if CinemaPerson.isPerson(actor) then
        return E.walkItems(actor, j, function(s, fn)
            edit(s, function() s:keepOnRoute(actor, fn) end)
            s.actorRt = {}
        end)
    end
    local function kmh(p)
        return p[3] or actor.speed or E.ACTOR_SPEED_DEFAULT
    end
    local function change(s, delta)
        edit(s, function() s:keepOnRoute(actor, function()
            p1[3] = M.clamp(kmh(p1) + delta, 0, 80)
            p2[3] = M.clamp(kmh(p2) + delta, 0, 80)
        end) end)
        s.actorRt = {}
    end
    return {
        stepItem(function() return string.format(t("cine_menu_routeSpanFaster"), j, j + 1, E.speedStepOf(), math.max(kmh(p1), kmh(p2))) end,
            function(s) change(s, s.speedStep) end, function(s) change(s, -s.speedStep) end),
    }
end

-- Menu bloku jízdy (úsek, pauza, stání) herce i; tm = čas kliknutí (rozdělení tady).
function CinemaEditorScreen:openSpanMenu(i, e, x, y, tm)
    local actor = self.shot.actors[i]
    if actor == nil then
        return
    end
    local function current()
        for _, other in ipairs(self:actorSpanList(i)) do
            if other.kind == e.kind and other.j == e.j and other.k == e.k then
                return other
            end
        end
        return e
    end
    local items, title = {}, ""
    if e.kind == "wait" then
        title = string.format(t("cine_menu_waitTitle"), e.j)
        local function step(s, d)
            local now = current()
            s:pushUndo()
            local wait = math.max(now.t1 - now.t0 + d, 0)
            s:setPointWait(i, e.j, wait >= 0.05 and wait or nil)
            s.actorRt = {}
            S.touch(s.shot)
            s:markDirty()
        end
        items[#items + 1] = stepItem(function() local now = current() return string.format(t("cine_menu_waitLength"), now.t1 - now.t0) end,
            function(s) step(s, 1) end, function(s) step(s, -1) end)
        items[#items + 1] = item(t("cine_menu_waitDelete"), function(s) s:pushUndo() s:deleteSpanEntry(i, e) end)
    elseif e.kind == "stop" then
        title = t("cine_menu_stopTitle")
        local function step(s, d)
            local now = current()
            s:pushUndo()
            s:setStopLength(i, e.k, now.t1 - now.t0 + d)
        end
        items[#items + 1] = stepItem(function() local now = current() return string.format(t("cine_menu_stopLength"), now.t1 - now.t0) end,
            function(s) step(s, 1) end, function(s) step(s, -1) end)
        items[#items + 1] = item(t("cine_menu_stopDelete"), function(s) s:pushUndo() s:deleteSpanEntry(i, e) end)
    else
        local j = e.j
        title = string.format(t("cine_menu_spanTitle"), j, j + 1)
        for _, entry in ipairs(routeSpanItems(self, i, j)) do
            items[#items + 1] = entry
        end
        local curved = CinemaChannels.hasPoints(actor.curves ~= nil and actor.curves.speed or nil)
        local function length(s, d)
            local base = s:spanBase(i, j)
            if base ~= nil then
                s:pushUndo()
                s:setSpanDuration(i, j, math.max(base.dur0 + d, E.SPAN_MIN), base)
            end
        end
        items[#items + 1] = stepItem(function() local now = current() return string.format(t("cine_menu_spanDuration"), now.t1 - now.t0) end,
            function(s) length(s, E.SPAN_STEP) end, function(s) length(s, -E.SPAN_STEP) end, { disabled = curved })
        local function start(s, d)
            s:pushUndo()
            s:moveSpanStart(i, j, current().t0 + d)
        end
        items[#items + 1] = stepItem(function() return string.format(t("cine_menu_spanStart"), current().t0) end,
            function(s) start(s, E.SPAN_STEP) end, function(s) start(s, -E.SPAN_STEP) end)
        items[#items + 1] = item(t("cine_menu_spanSplit"), function(s)
            local now = current()
            if tm > now.t0 and tm < now.t1 then
                s:pushUndo()
                s:splitSpanAt(i, tm)
            end
        end)
        -- kamera nebo bod zájmu přesně na dobu úseku
        local first = actor.start ~= nil and actor.start.entries[1] or nil
        local vehicle = not CinemaPerson.isPerson(actor) and first ~= nil and W.find(first.uid) or nil
        local modes = {}
        for _, mode in ipairs(Mo.ORDER) do
            modes[#modes + 1] = item(t("cine_mode_" .. mode), function(s)
                local now = current()
                local keep = s.playhead
                s.playhead = now.t0
                s:createTrack(mode, vehicle)
                s.playhead = keep
                local seg = S.segmentAt(s.shot, now.t0 + 1e-3)
                if seg ~= nil and math.abs(seg.t - now.t0) < 1e-3 then
                    seg.track.duration = math.max(now.t1 - now.t0, S.MIN_SEGMENT)
                    S.touch(s.shot)
                end
            end)
        end
        items[#items + 1] = item(t("cine_menu_spanCamera"), function(s) s:openMenu(t("cine_menu_spanCamera"), modes, x, y) end,
            { submenu = true, disabled = vehicle == nil })
        items[#items + 1] = item(t("cine_menu_spanFocus"), function(s)
            local now = current()
            local target = CinemaPerson.isPerson(actor) and S.personTarget(s.shot, actor) or (first ~= nil and first.uid or nil)
            if target ~= nil then
                s:pushUndo()
                S.addFocusBlock(s.shot, now.t0, target, now.t1 - now.t0)
                S.touch(s.shot)
                s:markDirty()
            end
        end)
        items[#items + 1] = item(t("cine_menu_spanDelete"), function(s) s:pushUndo() s:deleteSpanEntry(i, e) end)
    end
    items[#items + 1] = separator()
    items[#items + 1] = item(t("cine_menu_spanWhole"), function(s) s:selSet("drive", actor) end)
    local actorTitle, actorItems = self:actorMenuItems(i, x, y, nil)
    items[#items + 1] = groupItem(t("cine_menu_spanActor"), actorTitle, actorItems, x, y)
    self:openMenu(title, items, x, y)
end

local function vehicleOnly(entry)
    entry.vehicleOnly = true
    return entry
end

local function personOnly(entry)
    entry.personOnly = true
    return entry
end

local function notHelper(entry)
    entry.notHelper = true
    return entry
end

local function helperOnly(entry)
    entry.helperOnly = true
    return entry
end

local function helperTitle(name)
    return CinemaPerson.helperTitle(name)
end

-- Další (dir 1) nebo předchozí (-1) pomocník v pořadí HelperManageru; název herce se mění s ním, pokud ho uživatel
-- nepřejmenoval.
local function nextHelper(actor, dir)
    local list = CinemaPerson.helperChoices()
    if #list == 0 then
        return
    end
    local index = 0
    for k, helper in ipairs(list) do
        if helper.name == actor.helper then
            index = k
        end
    end
    local oldTitle = helperTitle(actor.helper)
    actor.helper = list[(index - 1 + (dir or 1)) % #list + 1].name
    if actor.name == oldTitle then
        actor.name = helperTitle(actor.helper)
    end
end

-- Start herce (poloha celé soupravy a její stav, u postavy hráče jeho poloha) tam, kde teď ve hře stojí; první bod trasy
-- se posune s ním.
function CinemaEditorScreen:rememberActorStart(i)
    local actor = self.shot.actors[i]
    if CinemaPerson.isPerson(actor) then
        edit(self, function()
            actor.start = CinemaPerson.captureStart()
            actor.points[1] = { actor.start.person.x, actor.start.person.z }
        end)
        self:showMessage(t("cine_msg_startRemembered"))
        return
    end
    local first = actor.start ~= nil and actor.start.entries[1] or nil
    local v = first ~= nil and W.find(first.uid) or nil
    if v == nil then
        self:showMessage(t("cine_msg_actorMissing"))
        return
    end
    edit(self, function()
        actor.start = W.captureStart(v)
        local vx, _, vz = getWorldTranslation(v.rootNode)
        actor.points[1] = { vx, vz }
    end)
    self.actorRt = {}
    self:showMessage(t("cine_msg_startRemembered"))
end

-- Stav soupravy herce (nádrže, bedna, špína, světla, složení…) z toho, jak je teď ve hře; poloha startu zůstane. Náhled
-- akcí na ukazateli se předtím vrátí, aby se nezapsal místo skutečného stavu.
function CinemaEditorScreen:rememberActorState(i)
    local actor = self.shot.actors[i]
    local first = actor ~= nil and actor.start ~= nil and actor.start.entries[1] or nil
    local v = first ~= nil and W.find(first.uid) or nil
    if v == nil then
        self:showMessage(t("cine_msg_actorMissing"))
        return
    end
    self:clearActorStates()
    local states = W.captureStart(v).states
    edit(self, function() actor.start.states = states end)
    self:showActorStates(self.playhead)
    self:showMessage(t("cine_msg_stateRemembered"))
end

E.FILL_STEP = 0.1

-- Naplnění nádrží vozidel (nafta, voda, koncentrát, náklad…) po 10 % a druh obsahu; store(článek, jednotka, hodnota) ho
-- navíc zapíše do startu herce, aby ho reset a přehrání obnovily (bez store se jen nastaví ve hře, třeba stroji mezi objekty).
function CinemaEditorScreen:openFillMenu(title, vehicles, store, x, y)
    local items = {}
    for e, v in ipairs(vehicles) do
        for _, u in ipairs(CinemaActions.fillUnits(v)) do
            local types = CinemaActions.fillTypesOf(v, u)
            local function current()
                local index = v:getFillUnitFillType(u)
                local capacity = math.max(v:getFillUnitCapacity(u) or 0, 1e-6)
                local ft = g_fillTypeManager:getFillTypeByIndex(index)
                if (ft == nil or ft.name == "UNKNOWN") and types[1] ~= nil then
                    return types[1], 0, capacity
                end
                return ft ~= nil and { index = index, name = ft.name, title = ft.title or ft.name } or nil, (v:getFillUnitFillLevel(u) or 0) / capacity, capacity
            end
            local function set(s, ft, share)
                local capacity = math.max(v:getFillUnitCapacity(u) or 0, 0)
                local value = CinemaActions.formatFill(ft.name, capacity * M.clamp(share, 0, 1))
                edit(s, function()
                    CinemaActions.KINDS.fill.apply(v, value, { sub = u })
                    if store ~= nil then
                        store(e, u, value)
                    end
                end)
            end
            local function step(s, dir)
                local ft, share = current()
                if ft ~= nil then
                    set(s, ft, (math.floor(share / E.FILL_STEP + 0.5) + dir) * E.FILL_STEP)
                end
            end
            local function cycle(s, dir)
                local ft, share = current()
                if ft == nil or #types < 2 then
                    return
                end
                local k = 1
                for j, other in ipairs(types) do
                    if other.index == ft.index then
                        k = j
                    end
                end
                set(s, types[(k - 1 + dir) % #types + 1], share)
            end
            items[#items + 1] = stepItem(function()
                local ft, share = current()
                return string.format(t("cine_menu_fillLevel"), W.name(v), u, ft ~= nil and ft.title or "?", share * 100)
            end, function(s) step(s, 1) end, function(s) step(s, -1) end)
            if #types > 1 then
                items[#items + 1] = stepItem(function()
                    local ft = current()
                    return string.format(t("cine_menu_fillType"), ft ~= nil and ft.title or "?")
                end, function(s) cycle(s, 1) end, function(s) cycle(s, -1) end)
            end
        end
    end
    if #items == 0 then
        self:showMessage(t("cine_msg_noFillUnits"))
        return
    end
    self:openMenu(title, items, x, y)
end

-- Naplnění soupravy herce i, zapsané do jeho startu.
function CinemaEditorScreen:openActorFillMenu(i, x, y)
    local actor = self.shot.actors[i]
    if actor == nil or actor.start == nil then
        return
    end
    self:openFillMenu(string.format(t("cine_menu_fillTitle"), actor.name or "?"), CinemaActions.vehicles(actor, 0), function(e, u, value)
        actor.start.states = actor.start.states or {}
        actor.start.states[string.format("fill:%d:%d", e, u)] = value
    end, x, y)
end

function CinemaEditorScreen:openActorMenu(i, x, y, span)
    local title, items = self:actorMenuItems(i, x, y, span)
    if title ~= nil then
        self:openMenu(title, items, x, y)
    end
end

-- Nadpis a položky menu herce i (span = úsek trasy pod kurzorem, jeho rychlost nahoře); nil bez herce.
function CinemaEditorScreen:actorMenuItems(i, x, y, span)
    local actor = self.shot.actors[i]
    if actor == nil then
        return nil
    end
    local title = actor.name or "?"
    local items = span ~= nil and routeSpanItems(self, i, span) or {}
    local function setDriver(s, dir)
        local first = actor.start ~= nil and actor.start.entries[1] or nil
        if not W.hasDriverSeat(first ~= nil and W.find(first.uid) or nil) then
            s:showMessage(t("cine_msg_noDriverSeat"))
            return
        end
        edit(s, function() actor.driver = E.nextDriver(actor.driver, dir) end)
    end
    local more = {
        item(function() return t(s_detailIs(self, i) and "cine_menu_detailOff" or "cine_menu_detailOn") end,
            function(s) s:setDetail(s:getDetail() == i and nil or i) end, { keepOpen = true }),
        item(function() return t(actor.pinActions and "cine_menu_pinOn" or "cine_menu_pinOff") end,
            function(s) edit(s, function() actor.pinActions = not actor.pinActions or nil end) end, { keepOpen = true }),
        item(t("cine_menu_resetHere"), function(s) s:resetActorsAt(s.playhead, true) end),
        notHelper(item(t("cine_menu_resetActor"), function(s)
            local ok, why = W.resetStart(actor.start)
            if not ok then
                s:showMessage(t(why == "noStart" and "cine_msg_actorNoStart" or "cine_msg_actorMissing"))
            end
        end)),
        separator(),
        item(t("cine_menu_routeUndo"), function(s)
            edit(s, function()
                if #actor.points > 1 then
                    table.remove(actor.points)
                end
            end)
            s.actorRt = {}
        end, { keepOpen = true }),
        item(t("cine_menu_routeClear"), function(s)
            edit(s, function()
                while #actor.points > 1 do
                    table.remove(actor.points)
                end
            end)
            s.actorRt = {}
        end),
        separator(),
        E.dockItem(),
    }
    for _, entry in ipairs({
        vehicleOnly(stepItem(function() return string.format(t("cine_menu_speedUp"), E.speedStepOf(), actor.speed) end,
            function(s) edit(s, function() s:keepOnRoute(actor, function() actor.speed = math.min(actor.speed + s.speedStep, 80) end) end) end,
            function(s) edit(s, function() s:keepOnRoute(actor, function() actor.speed = math.max(actor.speed - s.speedStep, 1) end) end) end)),
        stepItem(function() return string.format(t("cine_menu_delayUp"), actor.delay or 0) end,
            function(s) edit(s, function() actor.delay = (actor.delay or 0) + 0.5 end) end,
            function(s) edit(s, function() actor.delay = math.max((actor.delay or 0) - 0.5, -CinemaActions.earliest(actor), 0) end) end),
        vehicleOnly(item(t("cine_menu_vehicleAction"), function(s)
            s:openVehicleActionMenu(i, math.max(CinemaActions.minTime(actor), s.playhead - (actor.delay or 0)), x, y)
        end, { submenu = true })),
        personOnly(item(t("cine_menu_personAction"), function(s)
            s:openPersonActionMenu(i, math.max(CinemaActions.minTime(actor), s.playhead - (actor.delay or 0)), x, y)
        end, { submenu = true })),
        personOnly(item(t("cine_menu_povCamera"), function(s)
            local list = {}
            for _, variant in ipairs(Mo.POV_VARIANTS) do
                list[#list + 1] = item(t("cine_pov_" .. variant), function(s2) s2:createPovTrack(i, variant) end)
            end
            s:openMenu(t("cine_menu_povCamera"), list, x, y)
        end, { submenu = true })),
        separator(),
        item(t("cine_menu_drawRoute"), function(s)
            s.activeTarget = i
            if s.topdown == nil then
                s:enterTopdown()
            end
            s:showMessage(s:getActiveTargetText())
        end),
        notHelper(item(t("cine_menu_rememberStart"), function(s) s:rememberActorStart(i) end)),
        vehicleOnly(item(t("cine_menu_rememberState"), function(s) s:rememberActorState(i) end)),
        vehicleOnly(item(t("cine_menu_fill"), function(s) s:openActorFillMenu(i, x, y) end, { submenu = true })),
        separator(),
        vehicleOnly(stepItem(function()
            return string.format(t("cine_menu_driver"), actor.driver ~= nil and CinemaPerson.helperTitle(actor.driver) or t("cine_driver_none"))
        end, function(s) setDriver(s, 1) end, function(s) setDriver(s, -1) end)),
        helperOnly(stepItem(function() return string.format(t("cine_menu_helperLook"), helperTitle(actor.helper)) end,
            function(s) edit(s, function() nextHelper(actor, 1) end) end, function(s) edit(s, function() nextHelper(actor, -1) end) end)),
        helperOnly(item(t("cine_menu_wardrobe"), function(s)
            s:pushUndo()
            if not CinemaPerson.openWardrobe(actor) then
                table.remove(s.undoStack)
                s:showMessage(t("cine_msg_noWardrobe"))
            end
        end)),
        helperOnly(item(t("cine_look_reset"), function(s) edit(s, function() actor.look = nil end) end,
            { disabled = actor.look == nil })),
        item(t("cine_menu_rename"), function(s) s:openRenameActor(i) end),
        separator(),
        groupItem(t("cine_menu_more"), title, more, x, y),
        separator(),
        item(t("cine_menu_removeActor"), function(s) s:removeActor(i) end),
    }) do
        items[#items + 1] = entry
    end
    -- postava nemá řidiče ani akce vozidla; pomocník nemá start mimo trasu, jen vzhled
    local person, helper = CinemaPerson.isPerson(actor), CinemaPerson.isHelper(actor)
    for _, list in ipairs({ items, more }) do
        for k = #list, 1, -1 do
            local e = list[k]
            if (e.vehicleOnly and person) or (e.personOnly and not person) or (e.notHelper and helper) or (e.helperOnly and not helper) then
                table.remove(list, k)
            end
        end
        -- oddělovač na kraji nebo dva za sebou po vyřazení položek
        for k = #list, 1, -1 do
            if list[k].separator and (k == 1 or k == #list or (list[k + 1] ~= nil and list[k + 1].separator)) then
                table.remove(list, k)
            end
        end
    end
    return title, items
end

---------------------------------------------------------------------------------------------------
-- akce vozidel: cíl (celá souprava / článek), druh a hodnota; čas je vteřiny od startu vozidla

local function addAction(self, actorIndex, action, dur)
    local actor = self.shot.actors[actorIndex]
    self:pushUndo()
    if dur ~= nil then
        A.setDuration(action, dur)
    end
    self:setSelectedAction(actorIndex, A.add(actor, action))
    S.touch(self.shot)
    self:markDirty()
    self:showMessage(string.format(t("cine_msg_actionAdded"), A.label(action), action.t))
end

local function addVehicleAction(self, actorIndex, entry, kind, value, at, dur)
    addAction(self, actorIndex, { t = at, kind = kind, value = value, entry = entry }, dur)
end

E.PERSON_VEHICLE_RANGE = 40 -- m; vozidla v okolí postavy, která nabídka akcí postavy ukáže
E.PERSON_VEHICLE_LIMIT = 6

-- Vozidla pro akci postavy v čase at (s od startu postavy), která splní filtr: nejdřív vozidla herců záběru, pak
-- nejbližší vozidla kolem místa, kde postava v tu chvíli stojí.
function CinemaEditorScreen:personVehicles(actor, at, filter)
    local list, seen = {}, {}
    local function add(v)
        local uid = v ~= nil and W.uid(v) or nil
        if uid ~= nil and not seen[uid] and filter(v) then
            seen[uid] = true
            list[#list + 1] = v
        end
    end
    for _, a in ipairs(self.shot.actors) do
        for _, e in ipairs(a.start ~= nil and a.start.entries or {}) do
            add(W.find(e.uid))
        end
    end
    local x, z = CinemaPerson.poseAt(actor, at + (actor.delay or 0))
    local near = {}
    for _, v in ipairs(W.vehicles()) do
        if v.rootNode ~= nil and not v.isDeleted then
            local vx, _, vz = getWorldTranslation(v.rootNode)
            local d = math.sqrt((vx - x) ^ 2 + (vz - z) ^ 2)
            if d <= E.PERSON_VEHICLE_RANGE then
                near[#near + 1] = { v = v, d = d }
            end
        end
    end
    table.sort(near, function(a, b) return a.d < b.d end)
    for k = 1, #near do
        if #list >= #self.shot.actors + E.PERSON_VEHICLE_LIMIT then
            break
        end
        add(near[k].v)
    end
    return list
end

-- Akce postavy v čase at: nastoupit do vozidla, vystoupit, otevřít / zavřít animaci vozidla (dveře…). kind omezí
-- nabídku na jednu lajnu.
function CinemaEditorScreen:openPersonActionMenu(i, at, x, y, kind)
    local actor = self.shot.actors[i]
    if actor == nil then
        return
    end
    local items = {}
    if kind == nil or kind == "seat" then
        local seats = {}
        for _, v in ipairs(self:personVehicles(actor, at, A.KINDS.seat.available)) do
            seats[#seats + 1] = item(W.name(v), function(s)
                addAction(s, i, { t = at, kind = "seat", value = 1, entry = 0, vehicle = W.uid(v) })
            end)
        end
        items[#items + 1] = item(t("cine_act_seat_1"), function(s) s:openMenu(t("cine_act_seat_1"), seats, x, y) end,
            { submenu = true, disabled = #seats == 0 })
        items[#items + 1] = item(t("cine_act_seat_0"), function(s) addAction(s, i, { t = at, kind = "seat", value = 0, entry = 0 }) end)
    end
    if kind == nil or kind == "door" then
        local doors = {}
        for _, v in ipairs(self:personVehicles(actor, at, function(v) return #A.animationNames(v) > 0 end)) do
            doors[#doors + 1] = item(W.name(v), function(s) s:openDoorMenu(i, v, at, x, y) end, { submenu = true })
        end
        items[#items + 1] = item(t("cine_lane_door"), function(s) s:openMenu(t("cine_lane_door"), doors, x, y) end,
            { submenu = true, disabled = #doors == 0 })
    end
    if kind == nil or kind == "carry" then
        items[#items + 1] = item(t("cine_act_carry_1"), function(s) s:pickCarryTarget(i, at) end)
    end
    if kind == nil or kind == "jump" then
        items[#items + 1] = item(t("cine_act_jump_1"), function(s) addAction(s, i, { t = at, kind = "jump", value = 1, entry = 0 }) end)
    end
    self:openMenu(string.format(t("cine_menu_actionAtTitle"), at), items, x, y)
end

-- Nést předmět: výběr předmětu ve scéně (jako T) pro postavu i od času at.
function CinemaEditorScreen:pickCarryTarget(i, at)
    self.pendingAction = { carry = { actor = i, t = at } }
    self.picking = true
    self.boxPlacing = nil
    self:setClean(false)
    self:needCursor()
    self:showMessage(t("cine_msg_pickCarry"))
end

-- Předmět ke zvednutí pod kurzorem: malé vozidlo (paleta, kanystr) podle obrysu, jinak předmět mapy pod paprskem. nil,
-- když tam nic, co jde zvednout, není.
function CinemaEditorScreen:carryTargetAt(x, y)
    local c = W.candidateAt(self.pickCandidates or W.candidates(self.cam), x, y)
    local target = c ~= nil and c.vehicle ~= nil and CinemaPerson.carryFromVehicle(c.vehicle) or nil
    if target == nil then
        local shape = W.pickShape(self.cam, x, y)
        target = shape ~= nil and CinemaPerson.carryFromShape(shape) or nil
    end
    return target
end

function CinemaEditorScreen:carryPickAt(x, y, pending)
    self.picking = false
    self.pendingAction = nil
    local target = self:carryTargetAt(x, y)
    if target == nil then
        self:showMessage(t("cine_msg_noCarry"))
        return
    end
    addAction(self, pending.actor, { t = pending.t, kind = "carry", value = 1, entry = 0, carry = target, subLabel = target.name },
        A.DEFAULT_DURATION)
end

function CinemaEditorScreen:openDoorMenu(i, v, at, x, y)
    local items = {}
    for _, name in ipairs(A.animationNames(v)) do
        for _, value in ipairs({ 1, 0 }) do
            items[#items + 1] = item(string.format("%s %s", t("cine_act_door_" .. value), name), function(s)
                addAction(s, i, { t = at, kind = "door", value = value, entry = 0, vehicle = W.uid(v), anim = name })
            end)
        end
    end
    self:openMenu(W.name(v), items, x, y)
end

function CinemaEditorScreen:openVehicleActionMenu(i, at, x, y)
    local actor = self.shot.actors[i]
    if actor == nil then
        return
    end
    local entries = actor.start ~= nil and actor.start.entries or {}
    if #entries <= 1 then
        self:openVehicleActionKinds(i, 0, at, x, y)
        return
    end
    local items = { item(t("cine_act_wholeSet"), function(s) s:openVehicleActionKinds(i, 0, at, x, y) end, { submenu = true }) }
    for k, e in ipairs(entries) do
        local v = W.find(e.uid)
        items[#items + 1] = item(v ~= nil and W.name(v) or "?", function(s) s:openVehicleActionKinds(i, k, at, x, y) end, { disabled = v == nil, submenu = true })
    end
    self:openMenu(string.format(t("cine_menu_actionAtTitle"), at), items, x, y)
end

E.ATTACH_TARGET_RANGE = 40 -- m; zapřažitelná vozidla kolem startu tahače, která nabídka zapřažení ukáže
E.ATTACH_TARGET_LIMIT = 6

-- Vlek (nářadí, přívěs) pro zapřažení k herci i: vozidla ostatních herců, pak nejbližší zapřažitelná vozidla kolem jeho startu.
function CinemaEditorScreen:attachTargets(i)
    local actor = self.shot.actors[i]
    local first = actor.start ~= nil and actor.start.entries[1] or nil
    local own, list, seen = {}, {}, {}
    for _, e in ipairs(actor.start ~= nil and actor.start.entries or {}) do
        own[e.uid] = true
    end
    local function add(v)
        local uid = v ~= nil and W.uid(v) or nil
        if uid ~= nil and not seen[uid] and not own[uid] and v.spec_attachable ~= nil then
            seen[uid] = true
            list[#list + 1] = v
        end
    end
    for k, other in ipairs(self.shot.actors) do
        for _, e in ipairs(k ~= i and other.start ~= nil and other.start.entries or {}) do
            add(W.find(e.uid))
        end
    end
    if first ~= nil then
        local near = {}
        for _, v in ipairs(W.vehicles()) do
            if v.rootNode ~= nil and not v.isDeleted then
                local vx, _, vz = getWorldTranslation(v.rootNode)
                local d = math.sqrt((vx - first.x) ^ 2 + (vz - first.z) ^ 2)
                if d <= E.ATTACH_TARGET_RANGE then
                    near[#near + 1] = { v = v, d = d }
                end
            end
        end
        table.sort(near, function(a, b) return a.d < b.d end)
        for k = 1, #near do
            if #list >= #self.shot.actors + E.ATTACH_TARGET_LIMIT then
                break
            end
            add(near[k].v)
        end
    end
    return list
end

-- Zapřažení: vlek z nabídky (action.vehicle), nebo odpojení všeho, co vozidlo nese.
function CinemaEditorScreen:openAttachMenu(i, entry, at, x, y)
    local items = {}
    for _, v in ipairs(self:attachTargets(i)) do
        items[#items + 1] = item(string.format("%s – %s", t("cine_act_attach_1"), W.name(v)), function(s)
            addAction(s, i, { t = at, kind = "attach", value = 1, entry = entry, vehicle = W.uid(v) })
        end)
    end
    if #items == 0 then
        items[1] = item(t("cine_act_attachNone"), function() end, { disabled = true })
    end
    items[#items + 1] = separator()
    items[#items + 1] = item(t("cine_act_attach_0"), function(s) addVehicleAction(s, i, entry, "attach", 0, at) end)
    self:openMenu(t("cine_lane_attach"), items, x, y)
end

-- Obsah bedny vleku SprayDrone: plná bedna jednoho druhu, nebo prázdná.
function CinemaEditorScreen:openCanisterMenu(i, entry, at, x, y)
    local actor = self.shot.actors[i]
    local slots = 0
    for _, v in ipairs(A.vehicles(actor, entry)) do
        slots = math.max(slots, A.toolboxSlots(v) or 0)
    end
    local items = {}
    for _, name in ipairs({ "SDT_CONCENTRATE_FERTILIZER", "SDT_CONCENTRATE_HERBICIDE", "DIESEL" }) do
        local list = {}
        for k = 1, slots do
            list[k] = { fillType = name, liters = A.CANISTER_LITERS }
        end
        items[#items + 1] = item(string.format(t("cine_act_canisters_full"), A.fillTitle(name)), function(s)
            addAction(s, i, { t = at, kind = "canisters", value = 1, entry = entry, items = A.formatCanisters(list) })
        end, { disabled = slots == 0 })
    end
    items[#items + 1] = separator()
    items[#items + 1] = item(t("cine_act_canisters_0"), function(s) addVehicleAction(s, i, entry, "canisters", 0, at) end)
    self:openMenu(t("cine_lane_canisters"), items, x, y)
end

local PAYLOAD_MENUS = { attach = "openAttachMenu", canisters = "openCanisterMenu" }

local function actionItems(self, i, entry, at, onlyLights, x, y)
    local actor = self.shot.actors[i]
    local items, lights = {}, false
    for _, kind in ipairs(A.ORDER) do
        local def = A.KINDS[kind]
        local isLight = def.light == true
        local values = A.availableValues(actor, entry, kind)
        if #values > 0 and def.payload then
            if not onlyLights then
                items[#items + 1] = item(t("cine_lane_" .. kind), function(s) s[PAYLOAD_MENUS[kind]](s, i, entry, at, x, y) end, { submenu = true })
            end
        elseif #values > 0 and isLight and not onlyLights then
            lights = true
        elseif #values > 0 and isLight == onlyLights then
            for _, value in ipairs(values) do
                items[#items + 1] = item(t(string.format("cine_act_%s_%d", kind, value)),
                    function(s) addVehicleAction(s, i, entry, kind, value, at) end)
            end
        end
    end
    return items, lights
end

function CinemaEditorScreen:openVehicleActionKinds(i, entry, at, x, y)
    local items, lights = actionItems(self, i, entry, at, false, x, y)
    if lights then
        table.insert(items, 1, item(t("cine_act_group_lights"), function(s) s:openVehicleLightMenu(i, entry, at, x, y) end, { submenu = true }))
    end
    if #items == 0 then
        items[1] = item(t("cine_act_none"), function() end, { disabled = true })
    end
    self:openMenu(string.format(t("cine_menu_actionAtTitle"), at), items, x, y)
end

function CinemaEditorScreen:openVehicleLightMenu(i, entry, at, x, y)
    self:openMenu(t("cine_act_group_lights"), (actionItems(self, i, entry, at, true, x, y)), x, y)
end

-- Menu prázdného místa v lajně: akce tohoto druhu od času at (s od startu vozidla), i na dobu.
function CinemaEditorScreen:openLaneMenu(i, kind, at, x, y)
    local actor = self.shot.actors[i]
    local def = A.KINDS[kind]
    if actor == nil or def == nil then
        return
    end
    if def.person then
        self:openPersonActionMenu(i, at, x, y, kind)
        return
    end
    if def.payload then
        self[PAYLOAD_MENUS[kind]](self, i, 0, at, x, y)
        return
    end
    local values = A.availableValues(actor, 0, kind)
    if #values == 0 then
        values = def.values
    end
    local items = {}
    for _, value in ipairs(values) do
        local label = t(string.format("cine_act_%s_%d", kind, value))
        items[#items + 1] = item(label, function(s) addVehicleAction(s, i, 0, kind, value, at) end)
        if A.canStretch({ kind = kind, value = value }) and not A.isBlink({ kind = kind, value = value }) then
            items[#items + 1] = item(string.format(t("cine_menu_laneFor"), label, A.DEFAULT_DURATION),
                function(s) addVehicleAction(s, i, 0, kind, value, at, A.DEFAULT_DURATION) end)
        end
    end
    self:openMenu(string.format(t("cine_menu_laneTitle"), t("cine_lane_" .. kind), at), items, x, y)
end

-- Menu značky akce na ose: posun v čase, délka, smazání.
function CinemaEditorScreen:openActionEditMenu(i, j, x, y)
    local actor = self.shot.actors[i]
    local action = actor ~= nil and actor.actions[j] or nil
    if action == nil then
        return
    end
    local function shift(s, delta)
        edit(s, function()
            for k, other in ipairs(actor.actions) do
                if other == action then
                    s:setSelectedAction(i, A.move(actor, k, action.t + delta))
                    break
                end
            end
        end)
    end
    -- blikání se prodlužuje a zkracuje po jednom bliknutí
    local step = A.isBlink(action) and A.BLINK_PERIOD or 0.5
    local items = {
        stepItem(function() return string.format(t("cine_menu_actionLater"), action.t, 0.5) end,
            function(s) shift(s, 0.5) end, function(s) shift(s, -0.5) end),
        stepItem(function() return string.format(t("cine_menu_actionLater"), action.t, 0.1) end,
            function(s) shift(s, 0.1) end, function(s) shift(s, -0.1) end),
        stepItem(function() return string.format(t("cine_menu_actionLonger"), A.endTime(action) - action.t) end,
            function(s) edit(s, function() A.setDuration(action, A.endTime(action) - action.t + step) end) end,
            function(s)
                if action.dur == nil and not A.isBlink(action) then
                    return
                end
                edit(s, function()
                    local shorter = A.endTime(action) - action.t - step
                    if A.isBlink(action) then
                        A.setDuration(action, math.max(shorter, A.BLINK_PERIOD))
                    else
                        A.setDuration(action, shorter >= A.MIN_DURATION and shorter or nil)
                    end
                end)
            end, { disabled = not A.canStretch(action) }),
        separator(),
        item(t("cine_menu_actionDelete"), function(s)
            edit(s, function()
                for k, other in ipairs(actor.actions) do
                    if other == action then
                        A.remove(actor, k)
                        break
                    end
                end
            end)
            s:selClear()
        end),
    }
    self:openMenu(string.format(t("cine_menu_actionEditTitle"), A.label(action)), items, x, y)
end

-- Menu Více z lišty osy: schránka a panely.
function CinemaEditorScreen:openMoreMenu(x, y)
    local items = {
        item(t("cine_tb_copy_h"), function(s) s:onActionCopy() end),
        item(t("cine_tb_paste_h"), function(s) s:onActionPaste() end, { disabled = E.clipboard == nil }),
        separator(),
        E.dockItem(),
        item(function() return t(self.historyOpen and "cine_menu_historyOn" or "cine_menu_historyOff") end,
            function(s) s:toggleHistory() end, { keepOpen = true }),
    }
    self:openMenu(t("cine_tb_more"), items, x, y)
end

-- Podmenu kamer vozidla: kamera bloku sedí na místě kamery vozidla (kabina, venkovní) a jede s ním.
function CinemaEditorScreen:openVehicleCamMenu(vehicle, x, y)
    local items = {}
    for k, camera in ipairs(W.vehicleCameras(vehicle)) do
        local label = string.format(t("cine_vehicleCam"), k)
        if camera.inside then
            label = string.format("%s (%s)", label, t("cine_vehicleCam_inside"))
        end
        items[#items + 1] = item(label, function(s) s:createMountTrack(vehicle, k) end)
    end
    if #items == 0 then
        self:showMessage(t("cine_msg_noVehicleCameras"))
        return
    end
    self:openMenu(string.format("%s – %s", t("cine_menu_vehicleCams"), W.name(vehicle)), items, x, y)
end

-- Cíl bloku: vozidla a postavy záběru, nebo libovolný objekt kliknutím ve scéně.
function CinemaEditorScreen:openRetargetMenu(seg, x, y)
    local items = {}
    for _, c in ipairs(self:focusCandidates()) do
        items[#items + 1] = item(function() return (seg.track.target == c.target and "> " or "") .. c.label end,
            function(s) s:retargetBlock(seg, c.target) end)
    end
    items[#items + 1] = item(t("cine_add_pickTarget"), function(s)
        s.pendingAction = { retarget = seg.id }
        s.picking = true
        s:needCursor()
        s:showMessage(t("cine_msg_pickTarget"))
    end)
    self:openMenu(E.trackLabel(seg.track), items, x, y)
end

function CinemaEditorScreen:retargetBlock(seg, target)
    edit(self, function() seg.track.target = target end)
    self:showMessage(string.format(t("cine_msg_blockTarget"), self:targetName(target) or "?"))
end

-- Podmenu dvou cílů: druhý cíl z vozidel a postav záběru.
function CinemaEditorScreen:openPairMenu(target, x, y)
    local items = {}
    for _, c in ipairs(self:focusCandidates()) do
        if c.target ~= target then
            items[#items + 1] = item(c.label, function(s) s:createPairTrack(target, c.target) end)
        end
    end
    if #items == 0 then
        self:showMessage(t("cine_msg_pairNone"))
        return
    end
    self:openMenu(string.format("%s – %s", t("cine_mode_pair"), self:targetName(target) or "?"), items, x, y)
end

-- Podmenu sledování: ze které strany cíle (vozidlo nebo cíl postavy) se natáčí.
function CinemaEditorScreen:openFollowMenu(vehicle, x, y)
    local target = type(vehicle) == "string" and vehicle or W.uid(vehicle)
    local items = {}
    for _, side in ipairs(Mo.FOLLOW_ORDER) do
        items[#items + 1] = item(t("cine_follow_" .. side), function(s) s:createTrackOn("follow", target, side) end)
    end
    self:openMenu(string.format("%s – %s", t("cine_mode_follow"), self:targetName(target) or "?"), items, x, y)
end

-- Cíl bez vlastního vozidla vybraný ve scéně (T): postava herce i (pak i její pohled a menu herce) nebo dron vleku. Režimy
-- kamery na něj, dva cíle a bod zájmu.
function CinemaEditorScreen:openTargetMenu(target, i, x, y)
    local actor = i ~= nil and self.shot.actors[i] or nil
    local items = {}
    for _, mode in ipairs(Mo.ORDER) do
        if mode == "follow" then
            items[#items + 1] = item(t("cine_menu_follow"), function(s) s:openFollowMenu(target, x, y) end, { submenu = true })
        else
            items[#items + 1] = item(t("cine_mode_" .. mode), function(s) s:createTrackOn(mode, target) end)
        end
    end
    if actor ~= nil then
        items[#items + 1] = item(t("cine_menu_povCamera"), function(s)
            local list = {}
            for _, variant in ipairs(Mo.POV_VARIANTS) do
                list[#list + 1] = item(t("cine_pov_" .. variant), function(s2) s2:createPovTrack(i, variant) end)
            end
            s:openMenu(t("cine_menu_povCamera"), list, x, y)
        end, { submenu = true })
    end
    items[#items + 1] = item(t("cine_menu_pair"), function(s) s:openPairMenu(target, x, y) end, { submenu = true })
    items[#items + 1] = separator()
    items[#items + 1] = item(t("cine_menu_lookAt"), function(s) s:setFocusHere(target) end)
    if actor ~= nil then
        items[#items + 1] = item(t("cine_menu_editActor"), function(s) s:openActorMenu(i, x, y) end, { submenu = true })
    end
    self:openMenu(self:targetName(target) or "?", items, x, y)
end

local REASONS_TEXT = { noStart = "cine_msg_actorNoStart", missing = "cine_msg_actorMissing" }

function CinemaEditorScreen:openObjectMenu(vehicle, x, y)
    local items = {}
    for _, mode in ipairs(Mo.ORDER) do
        if mode == "follow" then
            items[#items + 1] = item(t("cine_menu_follow"), function(s) s:openFollowMenu(vehicle, x, y) end, { submenu = true })
        else
            items[#items + 1] = item(t("cine_mode_" .. mode), function(s) s:createTrack(mode, vehicle) end)
        end
    end
    items[#items + 1] = item(t("cine_mode_mount"), function(s) s:createMountTrack(vehicle) end)
    items[#items + 1] = item(t("cine_menu_vehicleCams"), function(s) s:openVehicleCamMenu(vehicle, x, y) end,
        { submenu = true, disabled = #W.vehicleCameras(vehicle) == 0 })
    items[#items + 1] = item(t("cine_menu_pair"), function(s) s:openPairMenu(W.uid(vehicle), x, y) end, { submenu = true })
    items[#items + 1] = separator()
    items[#items + 1] = item(t("cine_menu_lookAt"), function(s) s:setFocusHere(vehicle) end)
    items[#items + 1] = item(t(self:findActor(vehicle) ~= nil and "cine_menu_editActor" or "cine_menu_addActor"),
        function(s) s:addActor(vehicle) end)
    if self:findActor(vehicle) ~= nil then
        items[#items + 1] = item(t("cine_menu_rememberStart"), function(s) s:rememberActorStart(s:findActor(vehicle)) end)
        items[#items + 1] = item(t("cine_menu_rememberState"), function(s) s:rememberActorState(s:findActor(vehicle)) end)
    end
    items[#items + 1] = item(t("cine_menu_fill"), function(s)
        local index = s:findActor(vehicle)
        if index ~= nil then
            s:openActorFillMenu(index, x, y)
        else
            s:openFillMenu(W.name(vehicle), { vehicle }, nil, x, y)
        end
    end, { submenu = true })
    items[#items + 1] = item(t("cine_menu_addObject"), function(s) s:addObject(CinemaObjects.fromVehicle(vehicle)) end)
    items[#items + 1] = separator()
    local root = W.rootOf(vehicle)
    items[#items + 1] = item(t("cine_menu_dropHere"), function(s)
        local ok, why = W.dropAt(root, W.state(root).x, W.state(root).z)
        s:showMessage(g_i18n:getText(ok and "cine_msg_dropped" or (REASONS_TEXT[why] or "cine_msg_actorMissing")))
    end)
    items[#items + 1] = item(t("cine_menu_teleport"), function(s) s:startBoxPlace(CinemaBox.collect({ root }, {})) end)
    items[#items + 1] = item(t(CinemaBox.hasVehicle(root) and "cine_box_vehicleOut" or "cine_box_vehicleIn"), function(s)
        s:showMessage(string.format(t(CinemaBox.toggleVehicle(root) and "cine_msg_boxIn" or "cine_msg_boxOut"), W.name(root), CinemaBox.count()))
    end)
    self:openMenu(W.name(vehicle), items, x, y)
end
