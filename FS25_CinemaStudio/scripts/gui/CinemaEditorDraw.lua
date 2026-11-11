-- Kreslení editoru: náhled dráhy a tras ve 3D, obrysy objektů při výběru, časová osa s řádky vozidel, křivka
-- rychlosti, stavový řádek, letterbox, mřížka, hlášky a nápověda (F1).
-- Souřadnice obrazovky 0..1 od levého dolního rohu; velikosti v pixelech přes g_pixelSizeScaledX/Y.

local E = CinemaEditorScreen
local S = CinemaShot
local M = CinemaMath
local W = CinemaWorld
local R = CinemaRoute
local Cam = CinemaCamera
local Mo = CinemaModes
local A = CinemaActions
local Ch = CinemaChannels

-- Barvy UI podle presetů FS25 (sdk/xmlDoku/guiProfiles.xml, fs25_*): téměř černé plochy, tmavě šedé řádky a dlaždice,
-- jediný akcent zelený (fs25_colorMainHighlight / fs25_colorGreen), krémový text (fs25_colorMainLight).
E.UI = {
    panel = { 0.00439, 0.00478, 0.00368, 1 },
    cut = { 1, 0.35, 0.3, 1 },
    row = { 0.02956, 0.02956, 0.02956, 1 },
    rowActive = { 0.04231, 0.04231, 0.04231, 1 },
    rowFocus = { 0.06, 0.11, 0.012, 1 },
    button = { 0.04231, 0.04231, 0.04231, 1 },
    kbd = { 0.006, 0.0075, 0.004, 1 },
    kbdLit = { 0, 0, 0, 0.5 },
    topbar = { 0.00439, 0.00478, 0.00368, 0.93 },
    highlight = { 0.22323, 0.40724, 0.00368, 1 },
    accent = { 0.33716, 0.55834, 0.0003, 1 },
    separator = { 1, 1, 1, 0.05 },
    separatorLine = { 0.20156, 0.20156, 0.20156, 1 },
    lane = { 0.02732, 0.02732, 0.02732, 1 },
    track = { 0.04231, 0.04231, 0.04231, 1 },
    tick = { 0.20156, 0.20156, 0.20156, 1 },
    text = { 0.89627, 0.92158, 0.81485, 1 },
    dim = { 0.42, 0.43, 0.39, 1 },
    key = { 0.89627, 0.92158, 0.81485, 1 },
    keySelected = { 0.33716, 0.55834, 0.0003, 1 },
    keyHover = { 0.6, 0.8, 0.2, 1 },
    playhead = { 1, 0.22, 0.2, 1 },
    endMark = { 0.95, 0.6, 0.1, 1 },
    path = { 0.35, 0.8, 1, 0.9 },
    trackBlock = { 0.55, 0.35, 0.95, 0.95 },
    actor = { 0.35, 0.9, 0.45, 0.9 },
    actorActive = { 0.6, 1, 0.5, 1 },
    focus = { 0.8, 0.6, 1, 1 },
    routeKey = { 0.3, 0.65, 1, 1 },
    anchor = { 0.8, 0.6, 1, 1 },
    mark = { 1, 0.86, 0.3, 1 },
    focusBlend = { 1, 1, 1, 0.55 },
    pickBox = { 0.4, 0.9, 1, 0.75 },
    pickHover = { 1, 0.85, 0.2, 1 },
    boxed = { 1, 0.45, 0.85, 1 },
    curve = { 1, 0.62, 0.2, 1 },
    jerk = { 0.9, 0.15, 0.1, 1 },
    timeTick = { 1, 1, 1, 0.75 },
    message = { 0.00439, 0.00478, 0.00368, 0.92 },
    guide = { 1, 1, 1, 0.35 },
    snap = { 0.89627, 0.92158, 0.81485, 0.9 },
    marquee = { 0.33716, 0.55834, 0.0003, 0.16 },
}

-- 20 barev pro dráhy: kamera a každé vozidlo má svou, volí se čtverečkem vedle řádku na ose
E.PALETTE = {
    { 0.35, 0.80, 1.00 }, { 0.35, 0.90, 0.45 }, { 1.00, 0.62, 0.20 }, { 0.95, 0.35, 0.85 }, { 1.00, 0.90, 0.25 },
    { 1.00, 0.30, 0.30 }, { 0.65, 0.45, 1.00 }, { 0.20, 0.85, 0.75 }, { 1.00, 0.60, 0.70 }, { 0.70, 1.00, 0.30 },
    { 0.95, 0.95, 0.95 }, { 0.60, 0.62, 0.66 }, { 0.70, 0.50, 0.30 }, { 0.30, 0.40, 1.00 }, { 1.00, 0.50, 0.40 },
    { 0.60, 1.00, 0.80 }, { 0.90, 0.75, 0.20 }, { 0.60, 0.25, 0.50 }, { 0.60, 0.65, 0.20 }, { 0.70, 0.95, 1.00 },
}
E.PALETTE_COLUMNS = 5
E.CAM_COLOR_DEFAULT = 1
E.SWATCH_X = 0.016
E.SWATCH_PX = 13
E.EYE_X = 0.0265
E.EYE_PX = 15
E.CELL_PX = 24

E.TRACK_X0 = 0.14
E.TRACK_X1 = 0.965
E.TRACK_Y = 0.05
E.TRACK_H = 0.034
E.ROW_H = 0.028
E.ROW_GAP = 0.006
E.LABEL_X = 0.0465
E.STATUS_H = 0.008 -- odstup lišty osy od řádků (stav je v menu Stav, nápověda v liště)
E.ARROW_X0 = 0.0355 -- sbalení / rozbalení řádku vozidla (šipka mezi očičkem a názvem)
E.ARROW_X1 = 0.0455
E.ACTORS_MAX_H = 0.167 -- nejvyšší výška řádků vozidel (asi šest); co se nevejde, je za svislým posuvníkem
E.ROWS_BIG = 3 -- zvětšená osa: tolikrát víc místa pro řádky vozidel
E.ROWSCROLL_X = 0.972
E.ROWSCROLL_W = 0.007
E.CURVE_HEIGHT = 0.28
E.JERK_ACCEL = 4 -- m/s²; prudší změna rychlosti v Letu se na křivce rychlosti ukáže červeně
E.TIME_TICK = 0.5 -- s; časové značky na dráze kamery (hustě = pomalu)
E.KEY_PX = 9 -- velikost značky keyframu na ose
E.KEY_HIT_PX = 9 -- polovina šířky zásahu keyframu
E.TEXT_SIZE = 0.016
E.PATH_STEP = 0.5
E.PATH_CACHE_MS = 150 -- ms; jak dlouho platí vzorkovaná dráha kamery v živém režimu (cíl se čte živě)
E.DOT_PX = 12
E.ROUTE_KEY_PX = 7 -- šířka zásahu značky bodu trasy na ose
E.ACTION_HIT_PX = 8 -- polovina šířky zásahu značky akce vozidla
E.LANE_H = 0.02 -- výška lajny akcí nad řádkem vozidla
E.COLUMN_PX = 4 -- šířka sloupce profilu rychlosti v bloku
E.HANDLE_PX = 11 -- úchyt délky akce: tolik za značkou, než má akce délku
E.HANDLE_HIT_PX = 5 -- polovina šířky zásahu úchytu délky
E.LETTERBOX_RATIO = 2.39

local function color(c)
    return c[1], c[2], c[3], c[4] or 1
end

local function t_(key)
    return g_i18n:getText(key)
end

-- Ořez kreslení obsahu osy na pruh clipX0..clipX1 (nil = bez ořezu): přiblížená nebo posunutá osa nesmí zajet do levého
-- sloupce s názvy řádků. Obdélníky a čáry se oříznou, text s kotvou mimo pruh se nekreslí.
local clipX0, clipX1 = nil, nil

local function setClip(x0, x1)
    clipX0, clipX1 = x0, x1
end

local function rect(x, y, w, h, c)
    if clipX0 ~= nil then
        local right = math.min(x + w, clipX1)
        x = math.max(x, clipX0)
        w = right - x
        if w <= 0 then
            return
        end
    end
    drawFilledRect(x, y, w, h, color(c))
end

local function line(x1, y1, x2, y2, px, c)
    if clipX0 ~= nil then
        if x1 > x2 then
            x1, y1, x2, y2 = x2, y2, x1, y1
        end
        if x2 < clipX0 or x1 > clipX1 then
            return
        end
        if x1 < clipX0 then
            y1 = y1 + (y2 - y1) * (clipX0 - x1) / (x2 - x1)
            x1 = clipX0
        end
        if x2 > clipX1 then
            y2 = y2 - (y2 - y1) * (x2 - clipX1) / (x2 - x1)
            x2 = clipX1
        end
    end
    drawLine2D(x1, y1, x2, y2, px * g_pixelSizeX, color(c))
end

local function text(x, y, size, s, c, align, bold)
    if clipX0 ~= nil and (x < clipX0 - 1e-6 or x > clipX1 + 1e-6) then
        return
    end
    setTextColor(color(c or E.UI.text))
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    setTextBold(bold == true)
    renderText(x, y, size, s)
end

-- Kreslení bez ořezu (levý sloupec s názvy, popisky lajn).
local function unclipped(fn)
    local a, b = clipX0, clipX1
    clipX0, clipX1 = nil, nil
    fn()
    clipX0, clipX1 = a, b
end

-- Pro další soubory editoru (nástrojová lišta).
E.gfx = {}

local function resetText()
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
end

local function outline(x0, y0, x1, y1, px, c)
    line(x0, y0, x1, y0, px, c)
    line(x1, y0, x1, y1, px, c)
    line(x1, y1, x0, y1, px, c)
    line(x0, y1, x0, y0, px, c)
end
E.gfx.rect, E.gfx.line, E.gfx.text, E.gfx.outline = rect, line, text, outline
E.gfx.setClip = setClip

-- Ořez na pruh časové osy.
local function clipTrack()
    setClip(E.TRACK_X0, E.TRACK_X1)
end
E.gfx.clipTrack = clipTrack

---------------------------------------------------------------------------------------------------
-- rozvržení panelu a převody čas ↔ obrazovka

-- Řádek bodů zájmu je mezi kamerou a vozidly; je vidět, když nějaké body zájmu jsou, nebo když si ho uživatel přidal.
function CinemaEditorScreen:hasFocusRow()
    return (#self.shot.focus > 0 or self.shot.focusRow == true) and not self:isCompact()
end

-- Spodek řádku bodů zájmu; nil, když není vidět.
function CinemaEditorScreen:getFocusRowY()
    local row = self:rowLayout().byKey.focus
    return row ~= nil and row.y or nil
end

function CinemaEditorScreen:isFocusRowShown()
    return self:rowLayout().byKey.focus ~= nil
end

-- Spodek řádku kamery.
function CinemaEditorScreen:getCamRowY()
    return self:rowLayout().byKey.cam.y
end

-- Klíč řádku herce i na ose.
function CinemaEditorScreen:actorRowKey(i)
    return "a" .. S.actorId(self.shot, self.shot.actors[i])
end

-- Pořadí řádků osy odspodu (klíče "cam", "focus", "a<číslo herce>", "props" = skupina předmětů, "objects" = skupina objektů ve
-- světě), jak si je uživatel přeskládal; řádky, které
-- v uloženém pořadí chybí, jsou nahoře, zaniklé vypadnou. present[klíč] = true, u herce jeho index.
function CinemaEditorScreen:rowOrder()
    local shot = self.shot
    local present, defaults = { cam = true }, { "cam" }
    if self:hasFocusRow() then
        present.focus = true
        defaults[#defaults + 1] = "focus"
    end
    for i in ipairs(shot.actors) do
        if self:isActorListed(i) then
            local key = self:actorRowKey(i)
            present[key] = i
            defaults[#defaults + 1] = key
        end
    end
    if self:hasPropsRow() and self:getDetail() == nil then
        present.props = true
        defaults[#defaults + 1] = "props"
    end
    if self:hasObjectsRow() and self:getDetail() == nil then
        present.objects = true
        defaults[#defaults + 1] = "objects"
    end
    local order, seen = {}, {}
    for _, list in ipairs({ shot.rowOrder or {}, defaults }) do
        for _, key in ipairs(list) do
            if present[key] and not seen[key] then
                order[#order + 1] = key
                seen[key] = true
            end
        end
    end
    return order, present
end

-- Kamera a řádek bodů zájmu jsou vidět vždy, posouvají se jen řádky herců.
E.PINNED_ROWS = { cam = true, focus = true }

-- Rozvržení řádků: { rows = { { key, y, h, actor } } odspodu, byKey, top, scrolled = klíče herců v pořadí,
-- first / last = viditelný úsek z nich }. Okno herců má nejvýš E.ACTORS_MAX_H (zvětšená osa E.ROWS_BIG×), posouvá se
-- po celých hercích (rowScroll = kolik jich je pod oknem); jeden je vidět vždy, i kdyby byl vyšší.
function CinemaEditorScreen:rowLayout()
    if self.layoutFrozen ~= nil then
        return self.layoutFrozen
    end
    local order, present = self:rowOrder()
    local function height(key)
        if key == "cam" then
            return E.TRACK_H
        elseif key == "focus" then
            return E.ROW_H
        elseif key == "props" then
            return self:getPropsGroupH()
        elseif key == "objects" then
            return self:getObjectsGroupH()
        end
        return self:getActorFullH(present[key])
    end
    local scrolled = {}
    for _, key in ipairs(order) do
        if not E.PINNED_ROWS[key] then
            scrolled[#scrolled + 1] = key
        end
    end
    local maxH = E.ACTORS_MAX_H * (self.rowsBig and E.ROWS_BIG or 1)
    local n = #scrolled
    local first, last = 1, 0
    if n > 0 then
        local maxFirst, h = n, height(scrolled[n])
        while maxFirst > 1 and h + height(scrolled[maxFirst - 1]) <= maxH + 1e-6 do
            maxFirst = maxFirst - 1
            h = h + height(scrolled[maxFirst])
        end
        first = M.clamp((self.rowScroll or 0) + 1, 1, maxFirst)
        self.rowScroll = first - 1
        last = first
        local used = height(scrolled[first])
        while last < n and used + height(scrolled[last + 1]) <= maxH + 1e-6 do
            last = last + 1
            used = used + height(scrolled[last])
        end
    end
    local shown = { cam = true, focus = present.focus }
    for k = first, last do
        shown[scrolled[k]] = true
    end
    local rows, byKey = {}, {}
    local y, prev = E.TRACK_Y, nil
    for _, key in ipairs(order) do
        if shown[key] then
            -- kamera má od sousedů odstup
            if prev ~= nil and (key == "cam" or prev == "cam") then
                y = y + E.ROW_GAP
            end
            local row = { key = key, y = y, h = height(key), actor = type(present[key]) == "number" and present[key] or nil }
            rows[#rows + 1] = row
            byKey[key] = row
            y = y + row.h
            prev = key
        end
    end
    if prev == "cam" then
        y = y + E.ROW_GAP
    end
    -- okno osy má stálou výšku (jako při plném okně herců), jinak by se s každým přidaným nebo sbaleným řádkem posunulo
    -- všechno nad ním; vyšší je jen, když se jeden herec do okna nevejde
    local top = math.max(y, E.TRACK_Y + E.TRACK_H + 2 * E.ROW_GAP + E.ROW_H + maxH)
    return { rows = rows, byKey = byKey, top = top, rowsTop = y, scrolled = scrolled, first = first, last = last, present = present }
end

-- Řádek osy pod výškou y: řádek z rozvržení, nebo nil.
function CinemaEditorScreen:rowAtY(y)
    for _, row in ipairs(self:rowLayout().rows) do
        if y >= row.y and y <= row.y + row.h then
            return row
        end
    end
    return nil
end

-- Detailní vozidlo (číslo) nebo nil; zmizelé vozidlo detail ruší.
function CinemaEditorScreen:getDetail()
    if self.detail ~= nil and self.shot.actors[self.detail] == nil then
        self.detail = nil
    end
    return self.detail
end

-- Vozidlo patří na osu (detail jiného vozidla ho skryje); jestli je zrovna vidět, říká isActorShown.
function CinemaEditorScreen:isActorListed(i)
    local detail = self:getDetail()
    return detail == nil or detail == i
end

-- Výška bloku vozidla bez ohledu na posun řádků.
function CinemaEditorScreen:getActorFullH(i)
    return E.ROW_H + #self:getActorLanes(i) * E.LANE_H
end

-- Vozidla, která jsou v okně řádků vidět: index nejnižšího a nejvyššího zobrazeného (podle pořadí řádků).
function CinemaEditorScreen:getActorWindow()
    local layout = self:rowLayout()
    local first, last
    for k = layout.first, layout.last do
        local i = layout.present[layout.scrolled[k]]
        if type(i) == "number" then
            first = first or i
            last = i
        end
    end
    if first == nil then
        return 1, 0
    end
    return first, last
end

function CinemaEditorScreen:isActorShown(i)
    return self.shot.actors[i] ~= nil and self:rowLayout().byKey[self:actorRowKey(i)] ~= nil
end

-- Nevejdou se všechny řádky herců do okna?
function CinemaEditorScreen:hasRowScroll()
    if self:getDetail() ~= nil then
        return false
    end
    local layout = self:rowLayout()
    return layout.first > 1 or layout.last < #layout.scrolled
end

function CinemaEditorScreen:scrollRowsBy(steps)
    self.rowScroll = math.max((self.rowScroll or 0) + steps, 0)
    self:rowLayout()
end

-- Posune okno řádků tak, aby vozidlo i bylo vidět.
function CinemaEditorScreen:revealActor(i)
    if self.shot.actors[i] == nil or self:getDetail() ~= nil then
        return
    end
    local key = self:actorRowKey(i)
    for _ = 1, #self.shot.actors + 1 do
        local layout = self:rowLayout()
        local pos
        for k, other in ipairs(layout.scrolled) do
            if other == key then
                pos = k
            end
        end
        if pos == nil or (pos >= layout.first and pos <= layout.last) then
            return
        end
        self.rowScroll = pos < layout.first and pos - 1 or self.rowScroll + 1
    end
end

-- Je kurzor nad řádky vozidel, které se nevejdou? (kolečko je tam posouvá)
function CinemaEditorScreen:isOverActorRows()
    if not self.cursorShown or self.mouseX == nil or self.playing or self.clean or not self:hasRowScroll() then
        return false
    end
    local _, y0, _, h = self:getRowScrollRect()
    return self.mouseY >= y0 and self.mouseY <= y0 + h
end

-- Svislý posuvník řádků vozidel (vpravo od osy): x, y, w, h (od nejnižšího zobrazeného herce po vršek řádků).
function CinemaEditorScreen:getRowScrollRect()
    local layout = self:rowLayout()
    local y0 = layout.rowsTop
    for k = layout.first, layout.last do
        y0 = math.min(y0, layout.byKey[layout.scrolled[k]].y)
    end
    return E.ROWSCROLL_X, y0, E.ROWSCROLL_W, math.max(layout.rowsTop - y0, E.ROW_H)
end

-- Klik nebo tažení na posuvníku: první vidět bude herec podle výšky kurzoru.
function CinemaEditorScreen:rowScrollTo(y)
    local _, y0, _, h = self:getRowScrollRect()
    self.rowScroll = math.floor(M.clamp((y - y0) / h, 0, 1) * #self:rowLayout().scrolled)
    self:rowLayout()
end

-- Tlačítka vlevo pod osou (pod sloupcem názvů): + přidat do scény, rozbalit vše, sbalit vše a zbytek přepínač ukazatele.
-- { add, expand, collapse, mode } = { x, y, w, h }.
function CinemaEditorScreen:getBottomButtons()
    local by = E.SCROLL_Y + E.SCROLL_H + 0.002
    local bh = E.TRACK_Y - 0.014 - by
    local bw = bh / g_screenAspectRatio * 1.2
    local gap = 0.002
    local x = 0.008
    local out = {}
    for _, name in ipairs({ "add", "expand", "collapse" }) do
        out[name] = { x, by, bw, bh }
        x = x + bw + gap
    end
    -- končí před ikonou playheadu na nule, ať se na ni z nuly nechytá tlačítko
    out.mode = { x, by, E.TRACK_X0 - 0.026 - x, bh }
    return out
end

function CinemaEditorScreen:getAddActorRect()
    return unpack(self:getBottomButtons().add)
end

local function overRect(self, r)
    return self.mouseX ~= nil and self.menu == nil and self.drag == nil and self.mouseX >= r[1] and self.mouseX <= r[1] + r[3]
        and self.mouseY >= r[2] and self.mouseY <= r[2] + r[4]
end

-- + (přidat do scény), ▲ rozbalit všechny řádky, ▼ sbalit všechny řádky.
function CinemaEditorScreen:drawAddActorButton()
    local ui = E.UI
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    local buttons = self:getBottomButtons()
    for _, name in ipairs({ "add", "expand", "collapse" }) do
        local r = buttons[name]
        local hover = overRect(self, r)
        rect(r[1], r[2], r[3], r[4], hover and ui.highlight or ui.row)
        local cx, cy = r[1] + r[3] * 0.5, r[2] + r[4] * 0.5
        local c = hover and ui.text or ui.dim
        if name == "add" then
            rect(cx - 4 * px, cy - px, 8 * px, 2 * py, c)
            rect(cx - px, cy - 4 * py, 2 * px, 8 * py, c)
        else
            local dir = name == "expand" and 1 or -1
            for k = 0, 4 do
                local w = (4 - k) * px
                rect(cx - w, cy + dir * (k - 2) * py - py * 0.5, 2 * w + px, py, c)
            end
        end
    end
end

-- Rozbalí (on false) nebo sbalí (on true) všechny řádky osy: lajny akcí vozidel, skupiny předmětů a objektů, řádek bodů zájmu.
function CinemaEditorScreen:setAllRowsCollapsed(on)
    self.compactRows = on
    for _, actor in ipairs(self.shot.actors) do
        self.collapsed[S.uid(actor)] = on
    end
    if (self.shot.propsCollapsed == true) ~= on then
        self:toggleProps()
    end
    if (self.shot.objectsCollapsed == true) ~= on then
        self:toggleObjects()
    end
end

function CinemaEditorScreen:drawRowScroll()
    if not self:hasRowScroll() then
        return
    end
    local x, y, w, h = self:getRowScrollRect()
    local layout = self:rowLayout()
    local n, first, last = #layout.scrolled, layout.first, layout.last
    rect(x, y, w, h, E.UI.lane)
    rect(x, y + h * (first - 1) / n, w, h * (last - first + 1) / n, E.UI.keySelected)
end

-- Sbalit všechno: lajny akcí všech vozidel i řádek bodů zájmu; zůstane kamera a hlavní řádky vozidel.
function CinemaEditorScreen:isCompact()
    return self.compactRows == true
end

function CinemaEditorScreen:toggleCompact()
    self.compactRows = not self.compactRows
    for _, actor in ipairs(self.shot.actors) do
        self.collapsed[S.uid(actor)] = self.compactRows
    end
end

-- Druhy akcí, které mají u vozidla i vlastní lajnu: ty, které mají akce, a v detailu i vše, co vozidlo umí.
function CinemaEditorScreen:getActorLanes(i)
    if self:isActorCollapsed(i) then
        return {}
    end
    local actor = self.shot.actors[i]
    local want = {}
    for _, action in ipairs(actor ~= nil and actor.actions or {}) do
        want[action.kind] = true
    end
    if self:getDetail() == i then
        for _, kind in ipairs(self.detailKinds or {}) do
            want[kind] = true
        end
    end
    local list = {}
    for _, kind in ipairs(A.ORDER) do
        if want[kind] then
            list[#list + 1] = kind
        end
    end
    return list
end

-- Sbalené vozidlo ukazuje jen hlavní řádek. Bez volby uživatele se při víc než třech vozidlech sbalí všechna kromě vybraného
-- (panel by jinak přerostl obrazovku); detail vozidla ho vždy rozbalí.
function CinemaEditorScreen:isActorCollapsed(i)
    local actor = self.shot.actors[i]
    if actor == nil or self.detail == i then
        return false
    end
    local explicit = self.collapsed[S.uid(actor)]
    if explicit ~= nil then
        return explicit
    end
    return #self.shot.actors > 3 and i ~= self.activeTarget
end

function CinemaEditorScreen:toggleActorCollapsed(i)
    local actor = self.shot.actors[i]
    if actor ~= nil then
        self.collapsed[S.uid(actor)] = not self:isActorCollapsed(i)
    end
end

-- Výška bloku vozidla na ose: hlavní řádek a lajny akcí; skryté vozidlo (jiné v detailu) nemá nic.
function CinemaEditorScreen:getActorBlockH(i)
    if not self:isActorShown(i) then
        return 0
    end
    return E.ROW_H + #self:getActorLanes(i) * E.LANE_H
end

-- Spodek hlavního řádku vozidla i; i = počet + 1 (nebo skryté vozidlo) je horní okraj všech řádků.
function CinemaEditorScreen:getActorRowY(i)
    local layout = self:rowLayout()
    local row = self.shot.actors[i] ~= nil and layout.byKey[self:actorRowKey(i)] or nil
    return row ~= nil and row.y or layout.top
end

-- Spodek lajny číslo k (od hlavního řádku nahoru) vozidla i.
function CinemaEditorScreen:getLaneY(i, k)
    return self:getActorRowY(i) + E.ROW_H + (k - 1) * E.LANE_H
end

function CinemaEditorScreen:getCamColorIndex()
    return self.shot.camColor or E.CAM_COLOR_DEFAULT
end

function CinemaEditorScreen:getActorColorIndex(i)
    local a = self.shot.actors[i]
    return a ~= nil and a.color or (2 + (i - 1) % (#E.PALETTE - 1))
end

function E.paletteColor(index, alpha)
    local c = E.PALETTE[index] or E.PALETTE[1]
    return { c[1], c[2], c[3], alpha or 1 }
end

-- Čtvereček barvy vedle řádku: x, y, w, h (y je střed řádku)
function CinemaEditorScreen:getSwatchRect(centerY)
    local w, h = E.SWATCH_PX * g_pixelSizeScaledX, E.SWATCH_PX * g_pixelSizeScaledY
    return E.SWATCH_X, centerY - h * 0.5, w, h
end

-- Očičko vedle čtverečku barvy: x, y, w, h (y je střed řádku)
function CinemaEditorScreen:getEyeRect(centerY)
    local w, h = E.EYE_PX * g_pixelSizeScaledX, E.EYE_PX * g_pixelSizeScaledY
    return E.EYE_X, centerY - h * 0.5, w, h
end

-- Trasa kamery ("cam" nebo 0) nebo vozidla (číslo) se kreslí a dá se na ni klikat, dokud ji očičko neskryje.
function CinemaEditorScreen:isRouteShown(target)
    if target == "cam" or target == 0 then
        return not self.shot.camHidden
    end
    local a = self.shot.actors[target]
    return a ~= nil and not a.hidden
end

function CinemaEditorScreen:toggleRoute(target)
    self:pushUndo()
    if target == "cam" then
        self.shot.camHidden = not self.shot.camHidden or nil
    else
        local a = self.shot.actors[target]
        a.hidden = not a.hidden or nil
    end
    self:markDirty()
end

-- "cam" nebo číslo vozidla, jehož očičko je pod kurzorem
function CinemaEditorScreen:eyeAt(x, y)
    local function inside(centerY)
        local ex, ey, w, h = self:getEyeRect(centerY)
        return x >= ex - w * 0.1 and x <= ex + w * 1.1 and y >= ey - h * 0.2 and y <= ey + h * 1.2
    end
    if inside(self:getCamRowY() + E.TRACK_H * 0.5) then
        return "cam"
    end
    for i = 1, #self.shot.actors do
        if self:isActorShown(i) and inside(self:getActorRowY(i) + E.ROW_H * 0.5) then
            return i
        end
    end
    return nil
end

-- "cam" nebo číslo vozidla, jehož čtvereček je pod kurzorem
function CinemaEditorScreen:swatchAt(x, y)
    local function inside(centerY)
        local sx, sy, w, h = self:getSwatchRect(centerY)
        return x >= sx - w * 0.3 and x <= sx + w * 1.3 and y >= sy - h * 0.3 and y <= sy + h * 1.3
    end
    if inside(self:getCamRowY() + E.TRACK_H * 0.5) then
        return "cam"
    end
    for i = 1, #self.shot.actors do
        if self:isActorShown(i) and inside(self:getActorRowY(i) + E.ROW_H * 0.5) then
            return i
        end
    end
    return nil
end

-- Bod zájmu na řádku pod kurzorem
function CinemaEditorScreen:focusAtScreen(x)
    local halfW = E.KEY_HIT_PX * g_pixelSizeScaledX
    local best, bestDist = nil, halfW
    for i, f in ipairs(self.shot.focus) do
        local dist = math.abs(self:xAtTime(f.t) - x)
        if dist <= bestDist then
            best, bestDist = i, dist
        end
    end
    return best
end

---------------------------------------------------------------------------------------------------
-- výběr barvy

function CinemaEditorScreen:openPalette(target, x, y)
    self.palette = { target = target, x = x, y = y }
    self.drag = nil
end

function CinemaEditorScreen:getPaletteLayout()
    local cols = E.PALETTE_COLUMNS
    local rows = math.ceil(#E.PALETTE / cols)
    local cw, ch = E.CELL_PX * g_pixelSizeScaledX, E.CELL_PX * g_pixelSizeScaledY
    local width, height = cols * cw, rows * ch
    local x = M.clamp(self.palette.x, 0.005, 0.995 - width)
    local y = M.clamp(self.palette.y + 0.02, 0.005, 0.995 - height)
    return x, y, cw, ch, cols, rows
end

function CinemaEditorScreen:paletteCellAt(px, py)
    local x, y, cw, ch, cols, rows = self:getPaletteLayout()
    if px < x or py < y or px > x + cols * cw or py > y + rows * ch then
        return nil
    end
    local col = math.floor((px - x) / cw)
    local row = rows - 1 - math.floor((py - y) / ch)
    local index = row * cols + col + 1
    return E.PALETTE[index] ~= nil and index or nil
end

function CinemaEditorScreen:paletteMouseEvent(posX, posY, isDown, button)
    if not isDown or button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN then
        return
    end
    local index = button == Input.MOUSE_BUTTON_LEFT and self:paletteCellAt(posX, posY) or nil
    local target = self.palette.target
    self.palette = nil
    if index == nil then
        return
    end
    self:pushUndo()
    if target == "cam" then
        self.shot.camColor = index
    elseif self.shot.actors[target] ~= nil then
        self.shot.actors[target].color = index
    end
    self:markDirty()
end

function CinemaEditorScreen:drawPalette()
    local x, y, cw, ch, cols, rows = self:getPaletteLayout()
    local current = self.palette.target == "cam" and self:getCamColorIndex() or self:getActorColorIndex(self.palette.target)
    rect(x - 0.004, y - 0.006, cols * cw + 0.008, rows * ch + 0.012, { 0, 0, 0, 0.92 })
    for i, c in ipairs(E.PALETTE) do
        local col = (i - 1) % cols
        local row = rows - 1 - math.floor((i - 1) / cols)
        local cx, cy = x + col * cw, y + row * ch
        if i == current then
            rect(cx + cw * 0.04, cy + ch * 0.04, cw * 0.92, ch * 0.92, { 1, 1, 1, 1 })
        end
        rect(cx + cw * 0.12, cy + ch * 0.12, cw * 0.76, ch * 0.76, E.paletteColor(i))
    end
end

function CinemaEditorScreen:getPanelTop()
    return self:getActorRowY(#self.shot.actors + 1) + E.STATUS_H + E.TOOLBAR_H
end

-- Volá se při každém převodu čas ↔ obrazovka, proto mezipaměť na jeden snímek (konec jízdy vozidla staví trasu).
function CinemaEditorScreen:getTimelineRange()
    if self.rangeTime == g_time and self.rangeValue ~= nil then
        return self.rangeValue
    end
    local d = math.max(S.duration(self.shot), self.playhead)
    for i = 1, #self.shot.actors do
        d = math.max(d, self:actorEnd(i))
    end
    local value = math.max(10, math.ceil((d + 2) / 5) * 5)
    -- během tažení se osa jen prodlužuje: zkrácení by přeškálovalo všechno pod kurzorem a tažená věc by skákala
    if self.drag ~= nil then
        value = math.max(value, self.rangeHeld or value)
        self.rangeHeld = value
    else
        self.rangeHeld = nil
    end
    self.rangeTime, self.rangeValue = g_time, value
    return self.rangeValue
end

-- Výřez osy: celý záběr, nebo přiblížená část od viewStart o délce viewSpan (vše v sekundách).
E.VIEW_MIN = 2 -- s; nejužší výřez osy
E.SCROLL_Y = 0.002 -- spodní okraj posuvníku výřezu osy
E.SCROLL_H = 0.008 -- výška posuvníku výřezu osy
E.VIEW_STEP = 1.25 -- násobek délky výřezu za jedno cvaknutí kolečka nad pravítkem

function CinemaEditorScreen:getViewSpan()
    local full = self:getTimelineRange()
    return M.clamp(self.viewSpan or full, math.min(E.VIEW_MIN, full), full)
end

function CinemaEditorScreen:getViewStart()
    local full = self:getTimelineRange()
    return M.clamp(self.viewStart or 0, 0, full - self:getViewSpan())
end

function CinemaEditorScreen:xAtTime(t)
    return E.TRACK_X0 + (E.TRACK_X1 - E.TRACK_X0) * (t - self:getViewStart()) / self:getViewSpan()
end

function CinemaEditorScreen:timeAtX(x)
    local u = M.clamp((x - E.TRACK_X0) / (E.TRACK_X1 - E.TRACK_X0), 0, 1)
    return M.clamp(self:getViewStart() + u * self:getViewSpan(), 0, self:getTimelineRange())
end

-- Přiblížení / oddálení osy kolečkem nad pravítkem, střed přiblížení je pod kurzorem.
function CinemaEditorScreen:zoomTimeline(steps, anchorX)
    local full = self:getTimelineRange()
    local span, start = self:getViewSpan(), self:getViewStart()
    local t = self:timeAtX(anchorX)
    local newSpan = M.clamp(span / E.VIEW_STEP ^ steps, math.min(E.VIEW_MIN, full), full)
    local ratio = (t - start) / span
    if newSpan >= full - 1e-6 then
        self.viewSpan, self.viewStart = nil, nil
    else
        self.viewSpan = newSpan
        self.viewStart = t - ratio * newSpan
    end
end

-- Posun výřezu o dx obrazovkových jednotek (tažení středním tlačítkem na pravítku).
function CinemaEditorScreen:panTimelineBy(dx)
    local span = self:getViewSpan()
    self.viewStart = self:getViewStart() - dx / (E.TRACK_X1 - E.TRACK_X0) * span
end

-- Čas, kdy vozidlo i projede j-tým naklikaným bodem trasy; nil bez trasy.
function CinemaEditorScreen:routePointTime(i, j)
    local a = self.shot.actors[i]
    if CinemaPerson.isPerson(a) then
        return CinemaPerson.pointTime(a, j)
    end
    local plan = a ~= nil and R.plan(a) or nil
    if plan == nil or plan.route.ctrlS[j] == nil then
        return nil
    end
    return (a.delay or 0) + R.timeAtS(plan, plan.route.ctrlS[j])
end

-- Index bodu trasy vozidla i, jehož značka na ose je pod kurzorem.
function CinemaEditorScreen:routePointAtScreen(i, x)
    local a = self.shot.actors[i]
    local best, bestDist = nil, E.ROUTE_KEY_PX * g_pixelSizeScaledX
    for j = 1, #(a.points or {}) do
        local t = self:routePointTime(i, j)
        if t ~= nil then
            local dist = math.abs(self:xAtTime(t) - x)
            if dist <= bestDist then
                best, bestDist = j, dist
            end
        end
    end
    return best
end

-- Úchyt délky akce: x, kde končí její pruh (aspoň kousek za značkou); nil, když akci natáhnout nejde.
function CinemaEditorScreen:actionHandleX(a, action)
    if not A.canStretch(action) then
        return nil
    end
    local x0 = self:xAtTime((a.delay or 0) + action.t)
    local x1 = self:xAtTime((a.delay or 0) + A.endTime(action))
    return math.max(x1, x0 + E.HANDLE_PX * g_pixelSizeScaledX)
end

-- Akce vozidla i (v lajně kind, jinak v kterékoli), jejíž značka nebo pruh je pod kurzorem: index a část
-- ("end" = úchyt délky, "body" = značka nebo pruh).
function CinemaEditorScreen:actionAtScreen(i, x, kind)
    local a = self.shot.actors[i]
    local px = g_pixelSizeScaledX
    local best, bestPart, bestScore = nil, nil, math.huge
    for j, action in ipairs(a.actions or {}) do
        if kind == nil or action.kind == kind then
            local x0 = self:xAtTime((a.delay or 0) + action.t)
            local x1 = self:xAtTime((a.delay or 0) + A.endTime(action))
            local handle = self:actionHandleX(a, action)
            if handle ~= nil and math.abs(x - handle) <= E.HANDLE_HIT_PX * px and (best == nil or bestPart ~= "end") then
                best, bestPart, bestScore = j, "end", 0
            elseif bestPart ~= "end" then
                local score = nil
                if math.abs(x - x0) <= E.ACTION_HIT_PX * px then
                    score = math.abs(x - x0)
                elseif x > x0 and x <= x1 then
                    score = E.ACTION_HIT_PX * px + (x - x0)
                end
                if score ~= nil and score < bestScore then
                    best, bestPart, bestScore = j, "body", score
                end
            end
        end
    end
    return best, bestPart
end

-- Lajna akcí pod výškou y u vozidla i: druh akce, nebo nil (hlavní řádek).
function CinemaEditorScreen:laneAtScreen(i, y)
    local lane = math.floor((y - self:getActorRowY(i) - E.ROW_H) / E.LANE_H) + 1
    return self:getActorLanes(i)[lane]
end

-- Rychlost kamery (m/s) v čase t podle bloku, ve kterém je: Let přesně z K-framů, režim z posunu mezi dvěma blízkými
-- okamžiky uvnitř bloku; v mezeře kamera stojí. nil bez bloků.
function CinemaEditorScreen:cameraSpeedAt(t)
    local shot = self.shot
    if #shot.segments == 0 then
        return nil
    end
    local seg = S.segmentAt(shot, t)
    if seg == nil then
        return 0
    end
    if S.hasKeys(seg.track) then
        return S.flightSpeedAt(shot, seg.track, t - seg.t)
    end
    local t1, t2 = math.max(t - 0.1, seg.t), math.min(t + 0.1, S.segmentEnd(seg))
    if t2 - t1 < 1e-3 then
        return 0
    end
    local x1, y1, z1 = self:modePose(seg, t1, nil)
    local x2, y2, z2 = self:modePose(seg, t2, nil)
    if x1 == nil or x2 == nil then
        return 0
    end
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2) / (t2 - t1)
end

-- Rychlost vozidla i (km/h) podle plánu v čase t; nil bez trasy.
function CinemaEditorScreen:actorSpeedAt(i, t)
    local a = self.shot.actors[i]
    if CinemaPerson.isPerson(a) then
        return CinemaPerson.speedAt(a, t)
    end
    local plan = a ~= nil and R.plan(a) or nil
    if plan == nil then
        return nil
    end
    local local1, local2 = math.max(t - (a.delay or 0) - 0.2, 0), math.max(t - (a.delay or 0) + 0.2, 0.2)
    local _, _, s1 = R.positionAtTime(plan, local1)
    local _, _, s2 = R.positionAtTime(plan, local2)
    return math.abs(s2 - s1) / (local2 - local1) * 3.6
end

function CinemaEditorScreen:isOnActorBlock(i, x)
    local a = self.shot.actors[i]
    local x0 = self:xAtTime(a.delay or 0)
    local x1 = math.max(self:xAtTime(self:actorEnd(i)), x0 + 0.01)
    return x >= x0 and x <= x1
end

-- Křivka rychlosti kamery: spodek a výška grafu a rychlost nahoře (podle nejrychlejšího místa výřezu a K-framů);
-- počítá se jednou za snímek.
function CinemaEditorScreen:getCurveScale()
    local top = self:getPanelTop()
    local cache = self.curveScale
    if cache == nil or cache.time ~= g_time then
        local maxSpeed = 1
        local v0, span = self:getViewStart(), self:getViewSpan()
        for k = 0, 80 do
            maxSpeed = math.max(maxSpeed, self:cameraSpeedAt(v0 + span * k / 80) or 0)
        end
        for _, e in ipairs(S.allKeys(self.shot)) do
            maxSpeed = math.max(maxSpeed, (S.keySpeed(self.shot, e.seg.track, e.index)))
        end
        cache = { time = g_time, vmax = maxSpeed * 1.15 }
        self.curveScale = cache
    end
    return top + 0.012, E.CURVE_HEIGHT - E.CH_STRIP_H - 0.02, cache.vmax
end

-- Nastavená rychlost (km/h) bodu j trasy vozidla i.
function CinemaEditorScreen:routePointKmh(i, j)
    local a = self.shot.actors[i]
    return a.points[j][3] or a.speed or E.ACTOR_SPEED_DEFAULT
end

-- Bod K-framu na křivce rychlosti pod kurzorem: { seg, index }, nebo nil.
function CinemaEditorScreen:curveKeyAt(x, y)
    if x < E.TRACK_X0 or x > E.TRACK_X1 then
        return nil
    end
    local y0, h, vmax = self:getCurveScale()
    local best, bestDist = nil, 12 * g_pixelSizeScaledX
    for _, e in ipairs(S.allKeys(self.shot)) do
        local ky = y0 + h * S.keySpeed(self.shot, e.seg.track, e.index) / vmax
        local dist = math.sqrt((self:xAtTime(e.t) - x) ^ 2 + ((ky - y) / g_screenAspectRatio) ^ 2)
        if dist <= bestDist then
            best, bestDist = { seg = e.seg, index = e.index }, dist
        end
    end
    return best
end

-- Táhla vlivu vybraného K-framu na křivce rychlosti (jak dlouho trvá rozjezd a dojezd): { side, x, y, seg, index },
-- jen na stranách se sousedním K-framem.
function CinemaEditorScreen:curveHandles()
    local seg, index, key = self:selectedKey()
    if seg == nil or key == nil or not S.hasKeys(seg.track) or #seg.track.keys < 2
        or S.keyIsFree(self.shot, seg.track, index) then
        return {}
    end
    local keys = seg.track.keys
    local y0, h, vmax = self:getCurveScale()
    local ky = y0 + h * S.keySpeed(self.shot, seg.track, index) / vmax
    local out = {}
    local prev, nxt = S.anchorNeighbor(self.shot, seg.track, index, -1), S.anchorNeighbor(self.shot, seg.track, index, 1)
    if prev ~= nil then
        local t = key.t - S.influence(key, "in") * (key.t - keys[prev].t)
        out[#out + 1] = { side = "in", x = self:xAtTime(seg.t + t), y = ky, seg = seg, index = index }
    end
    if nxt ~= nil then
        local t = key.t + S.influence(key, "out") * (keys[nxt].t - key.t)
        out[#out + 1] = { side = "out", x = self:xAtTime(seg.t + t), y = ky, seg = seg, index = index }
    end
    return out
end

function CinemaEditorScreen:curveHandleAt(x, y)
    if x < E.TRACK_X0 or x > E.TRACK_X1 then
        return nil
    end
    local best, bestDist = nil, 9 * g_pixelSizeScaledX
    for _, hnd in ipairs(self:curveHandles()) do
        local dist = math.sqrt((hnd.x - x) ^ 2 + ((hnd.y - y) / g_screenAspectRatio) ^ 2)
        if dist <= bestDist then
            best, bestDist = hnd, dist
        end
    end
    return best
end

---------------------------------------------------------------------------------------------------

-- Časová osa během přehrávání (jen k nahlédnutí, bez zásahů myší).
-- Posuvník výřezu: pruh přes celou osu, jezdec ukazuje, která část záběru je vidět; táhnutím se posouvá.
function CinemaEditorScreen:drawScrollbar()
    local ui = E.UI
    local px = g_pixelSizeScaledX
    local full = self:getTimelineRange()
    local span, start = self:getViewSpan(), self:getViewStart()
    local width = E.TRACK_X1 - E.TRACK_X0
    rect(E.TRACK_X0, E.SCROLL_Y, width, E.SCROLL_H, ui.lane)
    local tx0 = E.TRACK_X0 + width * start / full
    local tw = math.max(width * span / full, 6 * px)
    rect(tx0, E.SCROLL_Y, tw, E.SCROLL_H, span < full and ui.keySelected or ui.dim)
end

-- Střed jezdce posuvníku se přesune pod kurzor.
function CinemaEditorScreen:scrollTo(x)
    local full = self:getTimelineRange()
    local span = self:getViewSpan()
    local u = M.clamp((x - E.TRACK_X0) / (E.TRACK_X1 - E.TRACK_X0), 0, 1)
    self.viewStart = u * full - span * 0.5
end

function CinemaEditorScreen:drawPlaybackTimeline()
    -- přiblížená osa jede s playheadem, aby ukazovala, co se právě děje
    local v0, span = self:getViewStart(), self:getViewSpan()
    if self.playhead < v0 or self.playhead > v0 + span then
        self.viewStart = self.playhead - span * 0.2
    end
    self:drawTimeline()
    self:drawScrollbar()
    resetText()
end

function CinemaEditorScreen:drawEditor()
    if self.letterbox then
        self:drawLetterbox()
    end
    if self.grid then
        self:drawGrid()
    end
    if self.clean then
        resetText()
        return
    end
    if self.crosshair then
        self:drawCrosshair()
    end
    if self.showHelp then
        -- nápověda přes celou obrazovku: texty osy by jinak prosvítaly (text se kreslí až po plochách)
        rect(0, 0, 1, 1, E.UI.panel)
        self:drawHelp()
        resetText()
        return
    end
    self:drawPath()
    self:drawRoutes()
    self:drawZones()
    if self.boxPlacing ~= nil then
        self:drawBoxPlace()
    elseif self.picking and self.pendingAction ~= nil and self.pendingAction.box then
        self:drawBoxPick()
    elseif self.picking and self.pendingAction ~= nil and self.pendingAction.prop == "bale" then
        self:drawBalePick()
    elseif self.picking then
        self:drawPick()
    else
        self.pickCandidates = nil
    end
    self:drawTimeline()
    self:drawToolbar()
    self:drawHover()
    self:drawScrollbar()
    if self.curves then
        self:drawCurves()
    end
    self:drawStatus()
    self:drawMessage()
    if self.dock ~= nil then
        self:drawDock()
    end
    if self.historyOpen then
        self:drawHistory()
    end
    if self.menu ~= nil then
        self:drawMenu()
    end
    if self.palette ~= nil then
        self:drawPalette()
    end
    resetText()
end

function CinemaEditorScreen:drawLetterbox()
    local visible = M.clamp(g_screenAspectRatio / E.LETTERBOX_RATIO, 0, 1)
    local bar = (1 - visible) * 0.5
    if bar > 0 then
        rect(0, 0, 1, bar, { 0, 0, 0, 1 })
        rect(0, 1 - bar, 1, bar, { 0, 0, 0, 1 })
    end
end

function CinemaEditorScreen:drawGrid()
    for _, f in ipairs({ 1 / 3, 2 / 3 }) do
        line(f, 0, f, 1, 1, E.UI.guide)
        line(0, f, 1, f, 1, E.UI.guide)
    end
end

local function drawWorldPolyline(cam, pts, px, c)
    local prevX, prevY = nil, nil
    for _, p in ipairs(pts) do
        local sx, sy = Cam.worldToScreen(cam, p[1], p[2], p[3])
        if sx ~= nil and prevX ~= nil then
            line(prevX, prevY, sx, sy, px, c)
        end
        prevX, prevY = sx, sy
    end
end

local function drawWorldMarker(cam, x, y, z, sizePx, c)
    local sx, sy, dist = Cam.worldToScreen(cam, x, y, z)
    if sx == nil then
        return nil
    end
    local px = sizePx or math.max(6, math.min(16, 160 / math.max(dist, 1)))
    local w, h = px * g_pixelSizeScaledX, px * g_pixelSizeScaledY
    rect(sx - w * 0.5 - g_pixelSizeScaledX, sy - h * 0.5 - g_pixelSizeScaledY, w + 2 * g_pixelSizeScaledX, h + 2 * g_pixelSizeScaledY, { 0, 0, 0, 1 })
    rect(sx - w * 0.5, sy - h * 0.5, w, h, c)
    return sx, sy, dist
end

-- Tečka na dráze v místě, kde je kamera / vozidlo v čase playheadu.
-- Kříž uprostřed obrazu; s vybraným hercem i značka, kam by padl bod trasy z pravého tlačítka (při rozhlížení míří
-- střed obrazu).
function CinemaEditorScreen:drawCrosshair()
    local arm, ah = 0.012, 0.012 * g_screenAspectRatio
    line(0.5 - arm, 0.5, 0.5 - arm * 0.3, 0.5, 2, E.UI.accent)
    line(0.5 + arm * 0.3, 0.5, 0.5 + arm, 0.5, 2, E.UI.accent)
    line(0.5, 0.5 - ah, 0.5, 0.5 - ah * 0.3, 2, E.UI.accent)
    line(0.5, 0.5 + ah * 0.3, 0.5, 0.5 + ah, 2, E.UI.accent)
    local actor = self.shot.actors[self.activeTarget]
    if actor ~= nil and self.topdown == nil then
        local px, py, pz = W.pickGround(self.cam, 0.5, 0.5)
        self.crosshairHit = px ~= nil and { px, py, pz } or nil
        if px ~= nil then
            drawWorldMarker(self.cam, px, py + 0.05, pz, 10, E.paletteColor(self:getActorColorIndex(self.activeTarget), 1))
        end
    else
        self.crosshairHit = nil
    end
end

local function drawWorldDot(cam, x, y, z, c)
    local sx, sy = Cam.worldToScreen(cam, x, y, z)
    if sx == nil then
        return
    end
    local w, h = E.DOT_PX * g_pixelSizeScaledX, E.DOT_PX * g_pixelSizeScaledY
    rect(sx - w * 0.5 - 2 * g_pixelSizeScaledX, sy - h * 0.5 - 2 * g_pixelSizeScaledY, w + 4 * g_pixelSizeScaledX, h + 4 * g_pixelSizeScaledY, { 1, 1, 1, 1 })
    rect(sx - w * 0.5, sy - h * 0.5, w, h, c)
end

-- Značka pózy ve 3D se směrem pohledu; s handle i úchyt natočení na konci čárky.
local function drawWorldPose(cam, x, y, z, q, c, handle)
    local sx, sy, dist = drawWorldMarker(cam, x, y, z, nil, c)
    if sx == nil then
        return
    end
    local yaw, pitch = M.quatToYawPitchRoll(q)
    local dx, dy, dz = M.forwardFromYawPitch(yaw, pitch)
    local len = math.max(1.5, dist * 0.08)
    local ex, ey = Cam.worldToScreen(cam, x + dx * len, y + dy * len, z + dz * len)
    if ex ~= nil then
        line(sx, sy, ex, ey, 2, c)
        if handle then
            local kw, kh = 11 * g_pixelSizeScaledX, 11 * g_pixelSizeScaledY
            rect(ex - kw * 0.5 - g_pixelSizeScaledX, ey - kh * 0.5 - g_pixelSizeScaledY, kw + 2 * g_pixelSizeScaledX, kh + 2 * g_pixelSizeScaledY, { 0, 0, 0, 1 })
            rect(ex - kw * 0.5, ey - kh * 0.5, kw, kh, c)
        end
    end
end

function CinemaEditorScreen:drawPath()
    local cam = self.cam
    local cameraActive = self.activeTarget == 0 or #self.shot.actors == 0
    local pathColor = E.paletteColor(self:getCamColorIndex(), cameraActive and 1 or 0.45)
    local pathWidth = cameraActive and 3 or 2
    local routeShown = self:isRouteShown(0)
    local handles = self.topdown ~= nil and self.activeTarget == 0
    for _, seg in ipairs(routeShown and self.shot.segments or {}) do
        local track = seg.track
        if S.hasKeys(track) then
            local flight = track.mode == S.FLIGHT
            drawWorldPolyline(cam, S.flightPath(self.shot, track, E.PATH_STEP), pathWidth, pathColor)
            -- časové značky: kde jsou hustě, kamera jede pomalu
            if #track.keys >= 2 then
                local t, last = track.keys[1].t, track.keys[#track.keys].t
                while t <= last + 1e-6 do
                    local tx, ty, tz = S.flightEvaluate(self.shot, track, t)
                    drawWorldMarker(cam, tx, ty, tz, 4, E.UI.timeTick)
                    t = t + E.TIME_TICK
                end
            end
            for _, k in ipairs(track.keys) do
                local q = k.q
                if not flight then
                    q = select(4, self:blockPose(seg, seg.t + k.t, nil)) or q
                end
                drawWorldPose(cam, k.x, k.y, k.z, q, self:selHas("key", k) and E.UI.keySelected or E.UI.key, handles and flight)
            end
        elseif Mo.STANDS[track.mode] then
            -- stojící kamera bloku: místo, odkud se natáčí
            local px, py, pz, q = self:modePose(seg, seg.t, nil)
            if px ~= nil then
                drawWorldPose(cam, px, py, pz, q, self:selHas("block", seg) and E.UI.keySelected or E.UI.anchor, false)
            end
        else
            -- blok v živém režimu: dráha podle plánované polohy cíle
            -- ~80 vzorků modePose na blok je drahých: dráha platí do změny záběru nebo bloku, nejdéle E.PATH_CACHE_MS
            -- (stav cíle se čte živě, takže bez vypršení by zastarala)
            local duration = track.duration or 0
            local cache = self.livePaths ~= nil and self.livePaths[seg] or nil
            if cache == nil or cache.version ~= self.shot.version or cache.t ~= seg.t or cache.duration ~= duration
                or g_time - cache.time > E.PATH_CACHE_MS then
                local pts = {}
                local step = math.max(duration / 80, 0.1)
                local t = seg.t
                while t < seg.t + duration + step * 0.5 do
                    local px, py, pz = self:modePose(seg, math.min(t, seg.t + duration), nil)
                    if px == nil then
                        break
                    end
                    pts[#pts + 1] = { px, py, pz }
                    t = t + step
                end
                cache = { pts = pts, version = self.shot.version, t = seg.t, duration = duration, time = g_time }
                self.livePaths = self.livePaths or setmetatable({}, { __mode = "k" })
                self.livePaths[seg] = cache
            end
            drawWorldPolyline(cam, cache.pts, pathWidth, pathColor)
        end
    end
    -- táhla dráhy vybraného K-framu (shora)
    for _, hnd in ipairs(handles and routeShown and self:pathHandleTips() or {}) do
        local k = hnd.seg.track.keys[hnd.index]
        drawWorldPolyline(cam, { { k.x, k.y, k.z }, { hnd.x, hnd.y, hnd.z } }, 1, E.UI.text)
        drawWorldMarker(cam, hnd.x, hnd.y, hnd.z, 9, E.UI.text)
    end
    local dx, dy, dz = self:evaluatePose(self.playhead, nil)
    if dx ~= nil then
        drawWorldDot(cam, dx, dy, dz, E.paletteColor(self:getCamColorIndex()))
    end
end

function CinemaEditorScreen:drawRoutes()
    local cam = self.cam
    for i, a in ipairs(self.shot.actors) do
        local active = i == self.activeTarget
        local c = E.paletteColor(self:getActorColorIndex(i), active and 1 or 0.45)
        local plan = R.plan(a)
        local routeShown = self:isRouteShown(i)
        if CinemaPerson.isPerson(a) then
            local dx, dz, _, dy = CinemaPerson.poseAt(a, self.playhead)
            drawWorldDot(cam, dx, dy + 0.6, dz, c)
        elseif plan ~= nil then
            local dx, dz = R.positionAtTime(plan, self.playhead - (a.delay or 0))
            drawWorldDot(cam, dx, W.terrainY(dx, dz) + 0.6, dz, c)
        end
        -- postava má trasu po částech (další začíná výstupem z vozidla); část bez výstupu na ose se nejde, je ztlumená
        local routes = {}
        if CinemaPerson.isPerson(a) then
            for _, leg in ipairs(CinemaPerson.legs(a)) do
                local legPlan = R.plan(leg.actor)
                if legPlan ~= nil then
                    routes[#routes + 1] = { route = legPlan.route, dim = leg.start == nil, points = leg.actor.points }
                end
            end
        elseif plan ~= nil then
            routes[1] = { route = plan.route }
        end
        for _, part in ipairs(routeShown and routes or {}) do
            local route = part.route
            local n = #route.xs
            local lineColor = part.dim and { c[1], c[2], c[3], c[4] * 0.35 } or c
            local reverseColor = { 1, 0.6, 0.25, lineColor[4] }
            -- světové body trasy s výškami terénu se počítají jednou: objekt trasy se při změně bodů nahradí novým
            local runs = route.drawRuns
            if runs == nil then
                runs = {}
                local pts, reverse = {}, route.revTo[2] == true
                local function flush()
                    runs[#runs + 1] = { pts = pts, reverse = reverse }
                end
                local function heightAt(k)
                    local x, z = route.xs[k], route.zs[k]
                    return part.points ~= nil and CinemaPerson.floorY(part.points, route, route.ss[k], x, z) or W.terrainY(x, z)
                end
                for k = 1, n, 2 do
                    local x, z = route.xs[k], route.zs[k]
                    local point = { x, heightAt(k) + 0.3, z }
                    local rev = route.revTo[math.min(k + 1, n)] == true
                    if rev ~= reverse then
                        pts[#pts + 1] = point
                        flush()
                        pts, reverse = { point }, rev
                    else
                        pts[#pts + 1] = point
                    end
                end
                pts[#pts + 1] = { route.xs[n], heightAt(n) + 0.3, route.zs[n] }
                flush()
                route.drawRuns = runs
            end
            for _, run in ipairs(runs) do
                drawWorldPolyline(cam, run.pts, active and 3 or 2, run.reverse and reverseColor or lineColor)
            end
        end
        local picked = self.topdown ~= nil and self.topdown.point or nil
        for k, p in ipairs(routeShown and a.points or {}) do
            local isPicked = active and picked ~= nil and picked.actor == i and picked.index == k
            local sx, sy = drawWorldMarker(cam, p[1], self:routePointY(a, p) + 0.3, p[2], isPicked and 12 or (k == 1 and 12 or 8),
                isPicked and E.UI.keySelected or c)
            if k == 1 and sx ~= nil then
                text(sx, sy + 0.014, E.TEXT_SIZE * 0.85, a.name or "?", c, RenderText.ALIGN_CENTER, active)
            end
        end
        -- postava shora: šipka natočení jen u bodů, kde je zadané (menu bodu); za konec se táhne
        if active and self.topdown ~= nil and routeShown and CinemaPerson.isPerson(a) then
            for k, p in ipairs(a.points) do
                if p[6] ~= nil then
                    local tx, ty, tz = self:faceTip(a, k)
                    local fc = E.UI.focus
                    drawWorldPolyline(cam, { { p[1], ty, p[2] }, { tx, ty, tz } }, 2, fc)
                    local sx, sy = drawWorldMarker(cam, tx, ty, tz, 7, fc)
                    if sx ~= nil then
                        text(sx, sy + 0.01, E.TEXT_SIZE * 0.75, string.format("%.0f°", CinemaPerson.azimuth(p[6])), fc, RenderText.ALIGN_CENTER, true)
                    end
                end
            end
        end
    end
end

function CinemaEditorScreen:drawPick()
    local pending = self.pendingAction
    if pending == nil or pending.object then
        self:drawObjectPick()
    end
    local list = self:pickList()
    self.pickCandidates = list
    local hover = W.candidateAt(list, self.mouseX, self.mouseY)
    for _, c in ipairs(list) do
        local b = c.box
        local isHover = c == hover
        outline(b[1], b[2], b[3], b[4], isHover and 3 or 1.5, isHover and E.UI.pickHover or E.UI.pickBox)
        if isHover then
            text((b[1] + b[3]) * 0.5, b[4] + 0.01, E.TEXT_SIZE, c.label or W.name(c.vehicle), E.UI.pickHover, RenderText.ALIGN_CENTER, true)
        end
    end
    -- nesení: co postava zvedne (i předmět mapy, který obrys nemá)
    if pending ~= nil and pending.carry ~= nil and self.mouseX ~= nil then
        local target = self:carryTargetAt(self.mouseX, self.mouseY)
        local label = target ~= nil and target.name or g_i18n:getText("cine_msg_noCarry")
        text(self.mouseX, self.mouseY + 0.02, E.TEXT_SIZE, label, target ~= nil and E.UI.pickHover or E.UI.dim, RenderText.ALIGN_CENTER, true)
        if target ~= nil then
            drawWorldMarker(self.cam, target.x, target.y + 0.1, target.z, 12, E.UI.pickHover)
        end
    end
end

-- Přepínač vlevo pod osou: playhead posouvá jen pravítko, nebo i klik a tažení věcí na ose.
function CinemaEditorScreen:drawPlayheadMode()
    local ui = E.UI
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    local bx, by, bw, bh = unpack(self:getBottomButtons().mode)
    local hover = self.drag == nil and self.menu == nil and self.mouseX ~= nil and self.mouseX >= bx and self.mouseX <= bx + bw
        and self.mouseY >= by and self.mouseY <= by + bh
    rect(bx, by, bw, bh, (hover or self.playheadAnywhere) and ui.rowActive or ui.row)
    local cx = bx + 0.008
    rect(cx - px, by + 3 * py, 2 * px, bh - 6 * py, ui.playhead)
    rect(cx - 3 * px, by + bh - 7 * py, 6 * px, 4 * py, ui.playhead)
    local label = g_i18n:getText(self.playheadAnywhere and "cine_ph_anywhere" or "cine_ph_ruler")
    local size = E.TEXT_SIZE * 0.75
    local room = bx + bw - (cx + 0.007) - 0.003
    if getTextWidth(size, label) > room then
        size = size * room / getTextWidth(size, label)
    end
    text(cx + 0.007, by + (bh - size) * 0.5 + py, size, label, self.playheadAnywhere and { 1, 1, 1, 1 } or ui.dim, RenderText.ALIGN_LEFT)
end

-- Očičko: oko s panenkou, přeškrtnuté, když je trasa skrytá.
local function drawEye(cx, cy, shown, c)
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    local a, b = E.EYE_PX * 0.5 * px, E.EYE_PX * 0.27 * py
    local steps = 14
    local prevX, prevY
    for k = 0, steps do
        local angle = k / steps * 2 * math.pi
        local x, y = cx + a * math.cos(angle), cy + b * math.sin(angle) * (1 - 0.25 * math.cos(angle) ^ 2)
        if prevX ~= nil then
            line(prevX, prevY, x, y, 1.5, c)
        end
        prevX, prevY = x, y
    end
    if shown then
        local w, h = 5 * px, 5 * py
        rect(cx - w * 0.5, cy - h * 0.5, w, h, c)
    else
        local sx, sy = a * 0.9, E.EYE_PX * 0.42 * py
        line(cx - sx, cy - sy - py, cx + sx, cy + sy - py, 3, { 0, 0, 0, 0.9 })
        line(cx - sx, cy - sy, cx + sx, cy + sy, 1.5, c)
    end
end

-- Pozadí řádku na ose, proužek aktivního řádku, čtvereček barvy, očičko trasy (target: "cam" / číslo vozidla) a název vlevo.
function CinemaEditorScreen:drawRowBase(ry, rh, active, label, colorIndex, target)
    unclipped(function() self:drawRowBaseUnclipped(ry, rh, active, label, colorIndex, target) end)
end

function CinemaEditorScreen:drawRowBaseUnclipped(ry, rh, active, label, colorIndex, target)
    local ui = E.UI
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    local w = E.TRACK_X1 + 0.008 - 0.004
    rect(0.004, ry, w, rh, active and ui.rowFocus or ui.row)
    rect(0.004, ry, w, py, ui.separator)
    if active then
        -- ovládaný řádek: podbarvení, rámeček a pruh vlevo, aby bylo jasné, kam míří šipky a K
        local c = ui.keySelected
        rect(0.004, ry, w, py, { c[1], c[2], c[3], 0.7 })
        rect(0.004, ry + rh - py, w, py, { c[1], c[2], c[3], 0.7 })
        rect(0.004, ry, 5 * px, rh, c)
    end
    if colorIndex ~= nil then
        local sx, sy, sw, sh = self:getSwatchRect(ry + rh * 0.5)
        rect(sx - px, sy - py, sw + 2 * px, sh + 2 * py, { 0, 0, 0, 0.9 })
        rect(sx, sy, sw, sh, E.paletteColor(colorIndex))
    end
    if target ~= nil then
        local shown = self:isRouteShown(target)
        local ex, _, ew = self:getEyeRect(ry + rh * 0.5)
        drawEye(ex + ew * 0.5, ry + rh * 0.5, shown, shown and (active and ui.keySelected or ui.text) or ui.dim)
    end
    local size = E.TEXT_SIZE * 0.78
    local maxWidth = E.TRACK_X0 - E.LABEL_X - 0.008
    local width = getTextWidth(size, label)
    if width > maxWidth then
        size = size * maxWidth / width
    end
    text(E.LABEL_X, ry + rh * 0.5 - size * 0.35, size, label, active and ui.keySelected or ui.dim, RenderText.ALIGN_LEFT, active)
end

local function keyMarker(x, cy, sizePx, c)
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    local w, h = sizePx * px, sizePx * py
    rect(x - w * 0.5 - px, cy - h * 0.5 - py, w + 2 * px, h + 2 * py, { 0, 0, 0, 0.9 })
    rect(x - w * 0.5, cy - h * 0.5, w, h, c)
end
E.gfx.keyMarker = keyMarker

-- Společné části bloku: obrys výběru, vybrané kusy, značka plynulého navázání a úchyty krajů.
function CinemaEditorScreen:drawBlockFrame(seg, ax, bx, by, bh)
    local ui = E.UI
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    if self:selHas("block", seg) then
        outline(ax, by, bx, by + bh, 1, ui.keySelected)
    end
    for _, p in ipairs(E.blockParts(seg)) do
        if self:selHas("part", p) then
            local px0, px1 = self:xAtTime(p.t0), self:xAtTime(p.t1)
            rect(px0, by, px1 - px0, bh, { 1, 1, 1, 0.18 })
            outline(px0, by, px1, by + bh, 1, ui.keySelected)
        end
    end
    if seg.track.smooth then
        -- plynulé navázání: klín od spodku k vršku přes dobu prolnutí
        local blend = math.min(seg.track.blend or S.SMOOTH_BLEND, (seg.track.duration or 1) * 0.5)
        line(ax, by, self:xAtTime(seg.t + blend), by + bh, 2, { 1, 1, 1, 0.8 })
    end
    for _, ex in ipairs({ ax, bx }) do
        rect(ex - px, by + bh * 0.08, 2 * px, bh * 0.22, { 1, 1, 1, 0.6 })
        rect(ex - px, by + bh * 0.7, 2 * px, bh * 0.22, { 1, 1, 1, 0.6 })
    end
end

-- Popisek bloku přilepený k levému okraji osy, i když blok začíná vlevo mimo výřez.
local function blockLabelX(ax)
    return math.max(ax, E.TRACK_X0) + 3 * g_pixelSizeScaledX
end

-- Blok Letu: profil rychlosti kamery, popisek (rychlost, ohnisko) a K-framy uvnitř.
function CinemaEditorScreen:drawFlightBlock(seg, y, h, camColor)
    local ui = E.UI
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    local shot, track = self.shot, seg.track
    local ax, bx = self:xAtTime(seg.t), self:xAtTime(S.segmentEnd(seg))
    local by, bh = y + h * 0.1, h * 0.8
    rect(ax, by, bx - ax, bh, { camColor[1], camColor[2], camColor[3], self:selHas("block", seg) and 0.4 or 0.22 })
    local vx0, vx1 = math.max(ax, E.TRACK_X0), math.min(bx, E.TRACK_X1)
    local top = 0
    if vx1 - vx0 > 2 * px and #track.keys >= 2 then
        local columns = math.max(2, math.min(60, math.floor((vx1 - vx0) / (E.COLUMN_PX * px))))
        local t0, t1 = self:timeAtX(vx0), self:timeAtX(vx1)
        local list = {}
        for k = 1, columns do
            local v = S.flightSpeedAt(shot, track, t0 + (t1 - t0) * (k - 0.5) / columns - seg.t)
            list[k] = v
            top = math.max(top, v)
        end
        self:drawProfileColumns(list, top, vx0, vx1, by, bh, camColor, 0.75)
    end
    rect(ax, by + bh - py, bx - ax, py, { camColor[1], camColor[2], camColor[3], 1 })
    self:drawBlockFrame(seg, ax, bx, by, bh)
    local focal0, focal1 = track.keys[1].focal, track.keys[#track.keys].focal
    local lens = math.abs(focal0 - focal1) < 0.5 and string.format("%.0f mm", focal0) or string.format("%.0f>%.0f mm", focal0, focal1)
    local label = string.format("%s  %.1f m/s  %s", E.trackLabel(track), S.flightAverage(shot, track), lens)
    local lx = blockLabelX(ax)
    if not self:drawBlockLabelAt(lx, by + bh * 0.5, label, E.TEXT_SIZE * 0.68, bx - lx) then
        self:drawBlockLabelAt(lx, by + bh * 0.5, E.trackLabel(track), E.TEXT_SIZE * 0.68, bx - lx)
    end
    local hover = self.drag == nil and self.menu == nil and self:keyAtScreen(self.mouseX, self.mouseY) or nil
    for i, k in ipairs(track.keys) do
        local selected = self:selHas("key", k)
        local c, size = ui.key, E.KEY_PX
        if selected then
            c, size = ui.keySelected, E.KEY_PX + 3
        elseif hover ~= nil and hover.seg == seg and hover.index == i then
            c = ui.keyHover
        end
        local kx, cy = self:xAtTime(seg.t + k.t), by + bh * 0.5
        rect(kx - px * 0.5, by, px, bh, { 0, 0, 0, 0.45 })
        if S.keyIsFree(self.shot, track, i) then
            -- jen natočení: menší, čas určuje průběh
            c, size = { c[1], c[2], c[3], 0.6 }, size - 3
        end
        keyMarker(kx, cy, size, c)
        if k.speed ~= nil then
            -- zadaná rychlost v K-framu (jinak přirozená z okolí): tečka nad značkou
            rect(kx - 1.5 * px, cy + (size * 0.5 + 3) * py, 3 * px, 3 * py, ui.curve)
        end
    end
end

-- Blok v živém režimu: profil rychlosti (rozjezd a dojezd) a úchyty pro tažení prostředním tlačítkem.
function CinemaEditorScreen:drawSegmentBlock(seg, index, y, h)
    local ui = E.UI
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    local ax, bx = self:xAtTime(seg.t), self:xAtTime(S.segmentEnd(seg))
    local by, bh = y + h * 0.1, h * 0.8
    local c = ui.trackBlock
    rect(ax, by, bx - ax, bh, { c[1], c[2], c[3], 0.28 })
    local duration = seg.track.duration or 0
    local columns = 48
    for k = 0, columns - 1 do
        local v = Mo.speedFactor(seg.track, duration * (k + 0.5) / columns)
        local x0 = ax + (bx - ax) * k / columns
        rect(x0, by, (bx - ax) / columns + px, bh * (0.12 + 0.55 * v), { c[1], c[2], c[3], 0.85 })
    end
    rect(ax, by + bh - py, bx - ax, py, { c[1], c[2], c[3], 1 })
    self:drawBlockFrame(seg, ax, bx, by, bh)
    if Mo.MOVING[seg.track.mode] then
        local a1, a2 = Mo.easeTimes(seg.track)
        for _, handle in ipairs({ { seg.t + a1, "in" }, { S.segmentEnd(seg) - a2, "out" } }) do
            local hx = self:xAtTime(handle[1])
            rect(hx - px, by, 2 * px, bh, { 1, 1, 1, 0.55 })
            local size = 6
            rect(hx - size * 0.5 * px, by + bh - size * py, size * px, size * py, { 1, 1, 1, 1 })
        end
    end
    local lx = blockLabelX(ax)
    self:drawBlockLabelAt(lx, by + bh * 0.5, E.trackLabel(seg.track), E.TEXT_SIZE * 0.72, bx - lx)
    for _, m in ipairs(seg.track.marks or {}) do
        local mx = self:xAtTime(seg.t + m.u * duration)
        local selected = self:selHas("mark", m)
        rect(mx - px * 0.5, by, px, bh, { 0, 0, 0, 0.55 })
        keyMarker(mx, by + bh * 0.5, selected and E.KEY_PX + 3 or E.KEY_PX - 1, selected and ui.keySelected or ui.mark)
        if selected then
            text(mx, by + bh + 0.004, E.TEXT_SIZE * 0.85, string.format("%d mm  x%.2f", m.focal or 35, m.speed or 1), ui.text, RenderText.ALIGN_CENTER, true)
        end
    end
    local shown = self.easeShown
    if shown ~= nil and shown.index == index and g_time - shown.time < 1500 then
        local hx = self:xAtTime(shown.side == "in" and seg.t + shown.value or S.segmentEnd(seg) - shown.value)
        text(hx, by + bh + 0.004, E.TEXT_SIZE * 0.85, string.format("%.1f s", shown.value), ui.text, RenderText.ALIGN_CENTER, true)
    end
end

function CinemaEditorScreen:drawTimeline()
    local ui = E.UI
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    local top = self:getPanelTop()
    local shot = self.shot
    rect(0, 0, 1, top, ui.panel)
    rect(0, top - py, 1, py, { 1, 1, 1, 0.16 })
    local x0, x1, y, h = E.TRACK_X0, E.TRACK_X1, E.TRACK_Y, E.TRACK_H
    local camY = self:getCamRowY()
    local camActive = self.activeTarget == 0 or #shot.actors == 0

    -- časové pravítko pod řádky
    local range = self:getViewSpan()
    local major = range <= 20 and 1 or (range <= 60 and 5 or 10)
    local labelEvery = range <= 20 and 2 or major * 2
    local minor = range <= 20 and major * 0.5 or major
    local v0 = self:getViewStart()
    local full = self:getTimelineRange()
    clipTrack()
    for k = math.floor(v0 / minor), math.ceil((v0 + range) / minor) do
        local t = k * minor
        if t >= 0 and t <= full then
            local x = self:xAtTime(t)
            local isMajor = math.abs(t / major - math.floor(t / major + 0.5)) < 1e-6
            rect(x, y - (isMajor and 0.009 or 0.005), px, isMajor and 0.009 or 0.005, ui.tick)
            if isMajor and t % labelEvery == 0 then
                text(x, y - 0.026, E.TEXT_SIZE * 0.75, string.format("%.1f s", t), ui.dim, RenderText.ALIGN_CENTER)
            end
        end
    end
    setClip(nil)
    self:drawPlayheadMode()

    -- řádek kamery: bloky (Let s K-framy, režimy) a mezery, ve kterých kamera stojí
    local camLabel = g_i18n:getText("cine_row_camera")
    if #shot.cameras > 1 then
        camLabel = string.format(g_i18n:getText("cine_row_cameraN"), shot.camIndex, #shot.cameras)
    end
    self:drawRowBase(camY, h, camActive, camLabel, self:getCamColorIndex(), "cam")
    text(E.ARROW_X0 + 0.002, camY + h * 0.5 - E.TEXT_SIZE * 0.3, E.TEXT_SIZE * 0.75, self:isCompact() and ">" or "v", ui.text, RenderText.ALIGN_LEFT, true)
    local camColor = E.paletteColor(self:getCamColorIndex(), 0.95)
    clipTrack()
    for i, seg in ipairs(shot.segments) do
        local nextSeg = shot.segments[i + 1]
        if nextSeg ~= nil then
            -- mezera: kamera drží poslední pózu bloku
            local gx0, gx1 = self:xAtTime(S.segmentEnd(seg)), self:xAtTime(nextSeg.t)
            rect(gx0, camY + h * 0.5 - py, gx1 - gx0, 2 * py, { 1, 1, 1, 0.25 })
        end
        if S.hasKeys(seg.track) then
            self:drawFlightBlock(seg, camY, h, camColor)
        else
            self:drawSegmentBlock(seg, i, camY, h)
        end
    end
    setClip(nil)

    if self:isFocusRowShown() then
        self:drawFocusRow()
    end
    self:drawPropsGroup()
    self:drawObjectsGroup()

    -- řádky vozidel: bloky jízdy po úsecích trasy s profilem rychlosti, nad nimi lajny akcí
    for i, a in ipairs(shot.actors) do
        if self:isActorShown(i) then
            self:drawActorBlock(i, a)
        end
    end
    self:drawRowScroll()
    self:drawAddActorButton()

    -- playhead: čára přes všechny řádky a štítek s časem (jen když je ve výřezu)
    local headX = self:xAtTime(self.playhead)
    local headTop = self:getActorRowY(#shot.actors + 1)
    local labelY = E.SCROLL_Y + E.SCROLL_H + 0.002
    local endX = shot.endMark ~= nil and self:xAtTime(shot.endMark) or nil
    if endX ~= nil and endX >= E.TRACK_X0 - 1e-6 and endX <= E.TRACK_X1 + 1e-6 then
        -- konec záběru: tady přehrávání skončí (nebo střihne na další záběr)
        rect(endX - px, labelY, 2 * px, headTop - labelY, ui.endMark)
        local size = E.TEXT_SIZE * 0.75
        local label = t_("cine_label_end")
        local lw = getTextWidth(size, label) + 0.008
        rect(endX - lw, labelY, lw, size + 0.008, ui.endMark)
        text(endX - 0.004, labelY + 0.004, size, label, { 1, 1, 1, 1 }, RenderText.ALIGN_RIGHT, true)
    end
    if headX >= E.TRACK_X0 - 1e-6 and headX <= E.TRACK_X1 + 1e-6 then
        rect(headX - px, labelY, 2 * px, headTop - labelY, ui.playhead)
        local label = string.format("%.1f s", self.playhead)
        local size = E.TEXT_SIZE * 0.85
        local lw = getTextWidth(size, label) + 0.01
        rect(headX - lw * 0.5, labelY, lw, size + 0.008, ui.playhead)
        text(headX, labelY + 0.004, size, label, { 1, 1, 1, 1 }, RenderText.ALIGN_CENTER, true)
    end

    local guide = self.snapGuide
    if guide ~= nil and self.drag ~= nil then
        clipTrack()
        rect(self:xAtTime(guide) - px, labelY, 2 * px, headTop - labelY, ui.snap)
        setClip(nil)
    end
    local drag = self.drag
    if drag ~= nil and drag.kind == "row" and drag.moved and drag.drop ~= nil then
        -- kam padne přetahovaný řádek
        rect(0.008, drag.drop.y - py, E.TRACK_X1 - 0.008, 3 * py, ui.keySelected)
    end
    if drag ~= nil and drag.kind == "marquee" and drag.moved then
        local mx0, mx1 = math.min(drag.x0, drag.x), math.max(drag.x0, drag.x)
        local my0, my1 = math.min(drag.y0, drag.y), math.max(drag.y0, drag.y)
        rect(mx0, my0, mx1 - mx0, my1 - my0, ui.marquee)
        outline(mx0, my0, mx1, my1, 1, ui.keySelected)
    end
end

-- Sloupce profilu rychlosti v obdélníku bloku; výška sloupce je podíl z největší rychlosti bloku.
local function drawProfile(list, top, x0, x1, y, h, c, alpha)
    local px = g_pixelSizeScaledX
    local count = #list
    local width = (x1 - x0) / count
    for k = 1, count do
        local v = top > 1e-6 and list[k] / top or 0
        rect(x0 + width * (k - 1), y, width + px, h * (0.1 + 0.75 * v), { c[1], c[2], c[3], alpha })
    end
end

function CinemaEditorScreen:drawProfileColumns(list, top, x0, x1, y, h, c, alpha)
    drawProfile(list, top, x0, x1, y, h, c, alpha)
end

-- Popisek na tmavém podkladu, aby byl čitelný přes profil; false, když se do šířky maxWidth nevejde.
local function drawBlockLabel(x, y, label, size, maxWidth, c)
    local width = getTextWidth(size, label)
    if width + 6 * g_pixelSizeScaledX > maxWidth then
        return false
    end
    rect(x - 2 * g_pixelSizeScaledX, y - 0.001, width + 4 * g_pixelSizeScaledX, size * 1.15, { 0, 0, 0, 0.55 })
    text(x, y, size, label, c, RenderText.ALIGN_LEFT, true)
    return true
end

function CinemaEditorScreen:drawBlockLabelAt(x, y, label, size, maxWidth)
    return drawBlockLabel(x, y, label, size, maxWidth, E.UI.text)
end

-- Rychlost vozidla i (km/h) po sloupcích úseku [t0, t1] (čas záběru) a největší z nich.
local PROFILE_CACHE_MAX = 256

-- Profil rychlosti vozidla se pamatuje u jeho plánu podle (t0, t1, sloupce): závisí jen na plánu a zpoždění, ne na snímku.
-- Plán se při změně bodů nebo rychlosti nahradí novým, takže stará čísla zmizí s ním; zpoždění je v klíči u celé cache.
function CinemaEditorScreen:actorProfile(i, t0, t1, columns)
    local a = self.shot.actors[i]
    local plan = a ~= nil and not CinemaPerson.isPerson(a) and R.plan(a) or nil
    local byStart
    if plan ~= nil then
        local cache = plan.profileCache
        if cache == nil or cache.delay ~= (a.delay or 0) or cache.count >= PROFILE_CACHE_MAX then
            cache = { delay = a.delay or 0, count = 0, items = {} }
            plan.profileCache = cache
        end
        local byEnd = cache.items[t0]
        if byEnd == nil then
            byEnd = {}
            cache.items[t0] = byEnd
        end
        byStart = byEnd[t1]
        if byStart == nil then
            byStart = {}
            byEnd[t1] = byStart
        end
        local hit = byStart[columns]
        if hit ~= nil then
            return hit.list, hit.top
        end
        cache.count = cache.count + 1
    end
    local list, top = {}, 0
    for k = 1, columns do
        local v = self:actorSpeedAt(i, t0 + (t1 - t0) * (k - 0.5) / columns) or 0
        list[k] = v
        top = math.max(top, v)
    end
    if byStart ~= nil then
        byStart[columns] = { list = list, top = top }
    end
    return list, top
end

-- Blok vozidla: hlavní řádek (jízda po úsecích mezi body trasy se sloupci rychlosti, pauzy, značky bodů) a lajny akcí.
function CinemaEditorScreen:drawActorBlock(i, a)
    local ui = E.UI
    local px = g_pixelSizeScaledX
    local ry = self:getActorRowY(i)
    local active = i == self.activeTarget
    self:drawRowBase(ry, E.ROW_H, active, a.name or "?", self:getActorColorIndex(i), i)
    text(E.ARROW_X0 + 0.002, ry + E.ROW_H * 0.5 - E.TEXT_SIZE * 0.3, E.TEXT_SIZE * 0.75, self:isActorCollapsed(i) and ">" or "v", #(a.actions or {}) > 0 and ui.text or ui.dim, RenderText.ALIGN_LEFT, true)
    clipTrack()
    local c = E.paletteColor(self:getActorColorIndex(i), active and 0.95 or 0.75)
    local plan = R.plan(a)
    local by, bh = ry + E.ROW_H * 0.14, E.ROW_H * 0.72
    local bx0 = self:xAtTime(a.delay or 0)
    local bx1 = math.max(self:xAtTime(self:actorEnd(i)), bx0 + 0.01)
    if self:selHas("drive", a) then
        outline(bx0, by, bx1, by + bh, 1, ui.keySelected)
    end
    -- časy bodů trasy jednou za blok (dřív se pro každý bod počítaly třikrát)
    local pointTimes = {}
    for j = 1, #(a.points or {}) do
        pointTimes[j] = self:routePointTime(i, j) or false
    end
    if plan == nil and #(a.points or {}) < 2 then
        rect(bx0, ry + E.ROW_H * 0.44, bx1 - bx0, E.ROW_H * 0.12, c)
    else
        local count = #a.points
        for j = 1, count - 1 do
            local wait = a.points[j][4] or 0
            -- mezi koncem části trasy a výstupem z vozidla postava nejde (sedí ve vozidle)
            if a.points[j + 1][7] then
                wait = math.huge
            end
            local from, to = pointTimes[j] or nil, pointTimes[j + 1] or nil
            if from ~= nil and to ~= nil then
                local t0, t1 = from + wait, to
                local x0, x1 = self:xAtTime(t0), self:xAtTime(t1)
                if x1 - x0 > 3 * px then
                    local reverse = a.points[j + 1][5] == true
                    local sc = reverse and { 1, 0.6, 0.25, c[4] } or c
                    rect(x0, by, x1 - x0, bh, { sc[1], sc[2], sc[3], 0.28 })
                    local columns = math.max(2, math.min(60, math.floor((x1 - x0) / (E.COLUMN_PX * px))))
                    local list, top = self:actorProfile(i, t0, t1, columns)
                    drawProfile(list, top, x0, x1, by, bh, sc, 0.8)
                    drawBlockLabel(x0 + 3 * px, by + bh * 0.42, string.format(g_i18n:getText(reverse and "cine_label_revKmh" or "cine_label_kmh"), top),
                        E.TEXT_SIZE * 0.62, x1 - x0, ui.text)
                end
            end
        end
    end
    -- stání z křivky rychlosti jako pauza: tmavý úsek s délkou (táhne se za jízdu za ním)
    local curve = a.curves ~= nil and a.curves.speed or nil
    for k = 2, #(curve ~= nil and curve.points or {}) do
        if CinemaChannels.isStopEnd(curve, k) then
            local s0, s1 = (a.delay or 0) + curve.points[k - 1].t, (a.delay or 0) + curve.points[k].t
            local wx = self:xAtTime(s0)
            local w = self:xAtTime(s1) - wx
            rect(wx, by, w, bh, { 0, 0, 0, 0.5 })
            local size = E.TEXT_SIZE * 0.62
            local label = string.format("%.1f s", s1 - s0)
            if getTextWidth(size, label) < w then
                text(wx + w * 0.5, by + bh * 0.3, size, label, ui.text, RenderText.ALIGN_CENTER, true)
            end
        end
    end
    -- vybrané bloky jízdy (úsek, pauza, stání) s úchytem délky na konci
    for _, e in ipairs(self:actorSpanList(i)) do
        local kind, obj = self:spanObject(i, e)
        if self:selHas(kind, obj) then
            local x0, x1 = self:xAtTime(e.t0), self:xAtTime(e.t1)
            outline(x0, by, x1, by + bh, 2, ui.keySelected)
            rect(x1 - 3 * px, by, 3 * px, bh, ui.keySelected)
        end
    end
    local picked = self.topdown ~= nil and self.topdown.point or nil
    for j = 1, #(a.points or {}) do
        local pt = pointTimes[j] or nil
        if pt ~= nil then
            local isPicked = picked ~= nil and picked.actor == i and picked.index == j
            local wait = a.points[j][4]
            if wait ~= nil and wait > 0 then
                local wx = self:xAtTime(pt)
                local w = self:xAtTime(pt + wait) - wx
                rect(wx, by, w, bh, { 0, 0, 0, 0.5 })
                local size = E.TEXT_SIZE * 0.62
                local label = string.format("%.0f s", wait)
                if getTextWidth(size, label) < w then
                    text(wx + w * 0.5, by + bh * 0.42, size, label, ui.text, RenderText.ALIGN_CENTER, true)
                end
            end
            local mc = isPicked and ui.keySelected or ui.routeKey
            local w = (isPicked and 3 or 2) * px
            rect(self:xAtTime(pt) - w * 0.5, ry + E.ROW_H * 0.1, w, E.ROW_H * 0.8, mc)
        end
    end
    setClip(nil)
    self:drawActorLanes(i, a)
end

-- Lajny akcí: jedna na druh, s názvem vlevo. Akce s délkou je pruh s úchytem na konci, ostatní značka.
function CinemaEditorScreen:drawActorLanes(i, a)
    local ui = E.UI
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    for k, kind in ipairs(self:getActorLanes(i)) do
        local ly = self:getLaneY(i, k)
        rect(0.004, ly, E.TRACK_X1 + 0.008 - 0.004, E.LANE_H, ui.lane)
        rect(0.004, ly, E.TRACK_X1 + 0.008 - 0.004, py, ui.separator)
        local labelSize = E.TEXT_SIZE * 0.66
        local label = g_i18n:getText("cine_lane_" .. kind)
        local maxWidth = E.TRACK_X0 - E.LABEL_X - 0.008
        local width = getTextWidth(labelSize, label)
        if width > maxWidth then
            labelSize = labelSize * maxWidth / width
        end
        text(E.LABEL_X + 0.006, ly + E.LANE_H * 0.5 - labelSize * 0.35, labelSize, label, ui.dim, RenderText.ALIGN_LEFT)
        clipTrack()
        for j, action in ipairs(a.actions or {}) do
            if action.kind == kind then
                self:drawLaneAction(i, a, j, action, ly, self:selHas("action", action))
            end
        end
        setClip(nil)
    end
end

function CinemaEditorScreen:drawLaneAction(i, a, j, action, ly, selected)
    local ui = E.UI
    local px = g_pixelSizeScaledX
    local c = A.color(action)
    local cy = ly + E.LANE_H * 0.5
    local x0 = self:xAtTime((a.delay or 0) + action.t)
    local x1 = self:xAtTime((a.delay or 0) + A.endTime(action))
    local size = E.TEXT_SIZE * 0.66
    local label = A.label(action)
    local isOff = (action.value or 1) == 0
    local textX = x0 + 8 * px
    if x1 > x0 then
        rect(x0, ly + E.LANE_H * 0.18, x1 - x0, E.LANE_H * 0.64, { c[1], c[2], c[3], selected and 0.95 or 0.7 })
        if A.isBlink(action) then
            -- zhasnuté půlky bliknutí tmavě, ať je počet vidět
            local count = A.blinkCount(action)
            local w = (x1 - x0) / count
            for k = 0, count - 1 do
                rect(x0 + (k + 0.5) * w, ly + E.LANE_H * 0.18, w * 0.5, E.LANE_H * 0.64, { 0, 0, 0, 0.35 })
            end
        end
        textX = x0 + 8 * px
        if getTextWidth(size, label) + 12 * px < x1 - x0 then
            text(textX, cy - size * 0.35, size, label, { 0, 0, 0, 0.9 }, RenderText.ALIGN_LEFT, true)
            label = nil
        end
    end
    local handle = self:actionHandleX(a, action)
    if handle ~= nil then
        rect(handle - px, ly + E.LANE_H * 0.12, 2 * px, E.LANE_H * 0.76, selected and ui.keySelected or { 1, 1, 1, 0.75 })
    end
    local markerSize = selected and E.KEY_PX + 1 or E.KEY_PX - 1
    keyMarker(x0, cy, markerSize, selected and ui.keySelected or (isOff and { c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, 1 } or { c[1], c[2], c[3], 1 }))
    if label ~= nil then
        local list = a.actions
        local nextX = math.huge
        for _, other in ipairs(list) do
            if other ~= action and other.kind == action.kind and other.t > action.t then
                nextX = math.min(nextX, self:xAtTime((a.delay or 0) + other.t))
            end
        end
        local lx = (handle or x0) + 8 * px
        local width = getTextWidth(size, label)
        if selected or lx + width + 4 * px < nextX then
            rect(lx - 2 * px, cy - size * 0.55, width + 4 * px, size * 1.3, { 0, 0, 0, 0.6 })
            text(lx, cy - size * 0.35, size, label, ui.text, RenderText.ALIGN_LEFT, selected)
        end
    end
end

function CinemaEditorScreen:drawFocusRow()
    local ui = E.UI
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    local shot = self.shot
    local ry = self:getFocusRowY()
    local range = self:getTimelineRange()
    self:drawRowBase(ry, E.ROW_H, false, g_i18n:getText("cine_focus_label"), nil)
    clipTrack()
    for i, f in ipairs(shot.focus) do
        local x0 = self:xAtTime(f.t)
        local x1 = shot.focus[i + 1] ~= nil and self:xAtTime(shot.focus[i + 1].t) or self:xAtTime(range)
        local selected = self:selHas("focus", f)
        if f.target ~= nil then
            local c = ui.focus
            rect(x0, ry + E.ROW_H * 0.22, math.max(x1 - x0, 2 * px), E.ROW_H * 0.56, { c[1], c[2], c[3], 0.5 })
            local blendEnd = self:xAtTime(f.t + (f.blend or S.FOCUS_BLEND))
            rect(x0, ry + E.ROW_H * 0.22, math.max(math.min(blendEnd, x1) - x0, 0), E.ROW_H * 0.12, ui.focusBlend)
            local label = self:targetName(f.target) or g_i18n:getText("cine_status_missing")
            text(x0 + 0.01, ry + E.ROW_H * 0.5 - E.TEXT_SIZE * 0.26, E.TEXT_SIZE * 0.72, label, { 0, 0, 0, 0.9 }, RenderText.ALIGN_LEFT, selected)
        elseif selected then
            -- bez cíle je řádek prázdný; vybraný úsek jen tenkým obrysem, ať je vidět, co se táhne
            outline(x0, ry + E.ROW_H * 0.22, math.max(x1, x0 + 2 * px), ry + E.ROW_H * 0.78, 1, ui.dim)
        end
        keyMarker(x0, ry + E.ROW_H * 0.5, selected and E.KEY_PX or E.KEY_PX - 2,
            selected and ui.keySelected or (f.target == nil and ui.dim or ui.key))
    end
    setClip(nil)
end

-- Graf rychlosti kamery (m/s) přes celou osu: v Letu body = K-framy s rychlostí, která se tažením nahoru a dolů mění
-- (pomalý nájezd, stálá rychlost, pomalý dojezd); v režimech jen průběh, v mezerách kamera stojí.
function CinemaEditorScreen:drawCamSpeedGraph()
    local ui = E.UI
    local shot = self.shot
    local top = self:getPanelTop()
    if #shot.segments == 0 then
        text(0.5, top + E.CURVE_HEIGHT * 0.45, E.TEXT_SIZE, g_i18n:getText("cine_curve_empty"), ui.dim, RenderText.ALIGN_CENTER)
        return
    end
    local y0, h, vmax = self:getCurveScale()
    -- vodorovné čáry po „hezkém" kroku rychlosti
    local step = vmax > 40 and 10 or (vmax > 12 and 5 or (vmax > 4 and 2 or 1))
    for v = 0, vmax, step do
        local gy = y0 + h * v / vmax
        rect(E.TRACK_X0, gy, E.TRACK_X1 - E.TRACK_X0, g_pixelSizeScaledY, ui.tick)
        text(E.TRACK_X0 + 0.003, gy + 0.002, E.TEXT_SIZE * 0.7, string.format("%d m/s", v), ui.dim)
    end
    clipTrack()
    -- kopeček: rychlost uprostřed úseku nad oběma K-framy, protože K-framy mají pevné časy (řeší Průběh rychlosti)
    for _, seg in ipairs(shot.segments) do
        if S.hasKeys(seg.track) then
            for _, hump in ipairs(S.flightHumps(shot, seg.track)) do
                local hx0, hx1 = self:xAtTime(seg.t + hump.from), self:xAtTime(seg.t + hump.to)
                rect(hx0, y0, hx1 - hx0, h, { ui.jerk[1], ui.jerk[2], ui.jerk[3], 0.14 })
                text((hx0 + hx1) * 0.5, y0 + h * math.min(hump.peak / vmax, 0.9) + 0.012, E.TEXT_SIZE * 0.72,
                    g_i18n:getText("cine_curve_hump"), ui.jerk, RenderText.ALIGN_CENTER, true)
            end
        end
    end
    local v0, range = self:getViewStart(), self:getViewSpan()
    local steps = 160
    local prevX, prevY, prevV, prevSeg
    for k = 0, steps do
        local tt = v0 + range * k / steps
        local v = self:cameraSpeedAt(tt) or 0
        local seg = S.segmentAt(shot, tt)
        local cx, cy = self:xAtTime(tt), y0 + h * v / vmax
        if prevX ~= nil then
            -- prudká změna rychlosti uvnitř Letu = škubnutí (střih mezi bloky se nepočítá)
            local jerk = seg ~= nil and seg == prevSeg and S.hasKeys(seg.track)
                and math.abs(v - prevV) / (range / steps) > E.JERK_ACCEL
            line(prevX, prevY, cx, cy, jerk and 3 or 2, jerk and ui.jerk or ui.curve)
        end
        prevX, prevY, prevV, prevSeg = cx, cy, v, seg
    end
    for _, hnd in ipairs(self:curveHandles()) do
        local kx = self:xAtTime(hnd.seg.t + hnd.seg.track.keys[hnd.index].t)
        line(kx, hnd.y, hnd.x, hnd.y, 1, ui.keySelected)
        local w, kh = 7 * g_pixelSizeScaledX, 7 * g_pixelSizeScaledY
        rect(hnd.x - w * 0.5 - g_pixelSizeScaledX, hnd.y - kh * 0.5 - g_pixelSizeScaledY, w + 2 * g_pixelSizeScaledX, kh + 2 * g_pixelSizeScaledY, { 0, 0, 0, 0.95 })
        rect(hnd.x - w * 0.5, hnd.y - kh * 0.5, w, kh, ui.text)
    end
    local shown = self.curveShown
    for _, e in ipairs(S.allKeys(shot)) do
        local v = S.keySpeed(shot, e.seg.track, e.index)
        local kx, ky = self:xAtTime(e.t), y0 + h * v / vmax
        local selected = self:selHas("key", e.key)
        local free = S.keyIsFree(shot, e.seg.track, e.index)
        local c = selected and ui.keySelected or ui.key
        -- jen natočení: menší a průhledný, rychlost v něm se netáhne
        local size = free and 6 or 10
        local w, kh = size * g_pixelSizeScaledX, size * g_pixelSizeScaledY
        rect(kx - w * 0.5 - g_pixelSizeScaledX, ky - kh * 0.5 - g_pixelSizeScaledY, w + 2 * g_pixelSizeScaledX, kh + 2 * g_pixelSizeScaledY, { 0, 0, 0, 0.95 })
        rect(kx - w * 0.5, ky - kh * 0.5, w, kh, free and { c[1], c[2], c[3], 0.45 } or c)
        if e.key.speed == nil and not free then
            rect(kx - g_pixelSizeScaledX, ky - g_pixelSizeScaledY, 2 * g_pixelSizeScaledX, 2 * g_pixelSizeScaledY, { 0, 0, 0, 0.9 })
        end
        if selected or (shown ~= nil and shown.key == e.key and g_time - shown.time < 1500) then
            local label = string.format("%.1f m/s", v)
            if selected and free then
                label = string.format(g_i18n:getText("cine_curve_keyFreeLabel"), v)
            elseif selected then
                label = string.format(g_i18n:getText("cine_curve_keyLabel"), v,
                    math.floor(S.influence(e.key, "in") * 100 + 0.5), math.floor(S.influence(e.key, "out") * 100 + 0.5))
            end
            text(kx, ky + 0.012, E.TEXT_SIZE * 0.78, label, ui.text, RenderText.ALIGN_CENTER, true)
        end
    end
    setClip(nil)
end

-- Zkrátí text, aby se vešel do šířky maxWidth.
local function fitText(label, size, maxWidth)
    if getTextWidth(size, label) <= maxWidth then
        return label
    end
    while #label > 1 and getTextWidth(size, label .. "..") > maxWidth do
        label = label:sub(1, -2)
    end
    return label .. ".."
end

-- Hezký krok mřížky pro rozsah.
local function niceStep(range)
    local raw = range / 5
    local pow = 10 ^ math.floor(math.log(raw) / math.log(10))
    local f = raw / pow
    return (f < 1.5 and 1 or (f < 3.5 and 2 or (f < 7.5 and 5 or 10))) * pow
end

-- Značka bodu kanálu: tvar podle režimu (úsečky čtverec, skok pruh, křivka čtverec s obrysem).
local function channelPoint(x, y, mode, c)
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    local w, h = 10 * px, 10 * py
    if mode == "step" then
        w, h = 14 * px, 6 * py
    end
    rect(x - w * 0.5 - px, y - h * 0.5 - py, w + 2 * px, h + 2 * py, { 0, 0, 0, 0.95 })
    rect(x - w * 0.5, y - h * 0.5, w, h, c)
    if mode == "smooth" then
        rect(x - px, y - py, 2 * px, 2 * py, { 0, 0, 0, 0.9 })
    end
end

-- Panel V: seznam kanálů vlevo (očičko, výběr), graf vybraného kanálu s ovládacími body, nahoře značky bodů trasy / keyframů.
function CinemaEditorScreen:drawCurves()
    local ui = E.UI
    local px, py = g_pixelSizeScaledX, g_pixelSizeScaledY
    local top = self:getPanelTop()
    local selected = self:selectedChannel()
    rect(0, top, 1, E.CURVE_HEIGHT, { 0.03, 0.033, 0.04, 1 })
    rect(0, top + E.CURVE_HEIGHT - py, 1, py, { 1, 1, 1, 0.16 })

    -- seznam kanálů
    local list = self:channelList()
    local rows = self:chVisibleRows()
    self.chScroll = M.clamp(self.chScroll or 0, 0, math.max(#list - rows, 0))
    local labelX = 0.034
    local labelWidth = E.TRACK_X0 - 0.01 - labelX
    for k = 0, rows - 1 do
        local entry = list[k + 1 + self.chScroll]
        if entry == nil then
            break
        end
        local ty = top + E.CURVE_HEIGHT - 0.008 - (k + 1) * E.CH_ROW
        if entry.header then
            text(0.006, ty + 0.004, E.TEXT_SIZE * 0.8, fitText(entry.label, E.TEXT_SIZE * 0.8, E.TRACK_X0 - 0.016), ui.dim, RenderText.ALIGN_LEFT, true)
        else
            local isSelected = selected ~= nil and selected.key == entry.key
            if isSelected then
                rect(0.002, ty, E.TRACK_X0 - 0.008, E.CH_ROW, ui.rowActive)
            end
            local ch = self:channelOf(entry, false)
            drawEye(0.0125, ty + E.CH_ROW * 0.5, not (ch ~= nil and ch.hidden), isSelected and ui.keySelected or ui.text)
            local c = self:channelColor(entry)
            rect(0.0235, ty + E.CH_ROW * 0.5 - 3 * py, 6 * px, 6 * py, { c[1], c[2], c[3], Ch.hasPoints(ch) and 1 or 0.35 })
            text(labelX, ty + 0.0045, E.TEXT_SIZE * 0.78, fitText(entry.label, E.TEXT_SIZE * 0.78, labelWidth),
                isSelected and ui.keySelected or ui.text, RenderText.ALIGN_LEFT, isSelected)
        end
    end

    -- plocha grafu
    local _, gx0, gx1, gy0, gy1 = self:chGeometry()
    rect(gx0, gy0, gx1 - gx0, gy1 - gy0, { 0.015, 0.017, 0.022, 1 })
    clipTrack()
    local v0, range = self:getViewStart(), self:getViewSpan()
    local steps = 200
    if selected ~= nil and selected.kind ~= "camspeed" then
        local lo, hi = self:channelRange(selected)
        local step = niceStep(hi - lo)
        for v = math.ceil(lo / step) * step, hi + 1e-9, step do
            local gy = gy0 + (gy1 - gy0) * (v - lo) / (hi - lo)
            rect(gx0, gy, gx1 - gx0, py, ui.tick)
            text(gx0 + 0.003, gy + 0.002, E.TEXT_SIZE * 0.7, string.format("%g %s", math.floor(v * 100 + 0.5) / 100, selected.unit or ""), ui.dim)
        end
    end
    setClip(nil)
    if selected ~= nil and selected.kind == "camspeed" then
        self:drawCamSpeedGraph()
    end
    clipTrack()
    -- křivky ostatních kanálů s body (tence, každá v rozsahu svého kanálu) a vybraného kanálu (tlustě)
    for _, entry in ipairs(list) do
        if not entry.header and entry.kind ~= "camspeed" then
            local ch = self:channelOf(entry, false)
            local isSelected = selected ~= nil and entry.key == selected.key
            if isSelected or (Ch.hasPoints(ch) and not ch.hidden) then
                local lo, hi = self:channelRange(entry)
                local c = self:channelColor(entry)
                local alpha = isSelected and 1 or 0.45
                local delay = self:channelDelay(entry)
                local prevX, prevY, prevActive
                for k = 0, steps do
                    local tt = v0 + range * k / steps
                    local v = self:channelValueAt(entry, tt)
                    if v ~= nil then
                        local cx, cy = self:xAtTime(tt), gy0 + (gy1 - gy0) * M.clamp((v - lo) / (hi - lo), 0, 1)
                        -- tlustě jen tam, kde kanál platí (mezi prvním a posledním bodem, u rychlosti i stání za koncovou nulou),
                        -- mimo to tence jako stín dosavadního průběhu
                        local active = Ch.isActive(ch, tt - delay) or (entry.kind == "speed" and CinemaRoute.curveStopped(ch, tt - delay))
                        if prevX ~= nil and (active or k % 2 == 0) then
                            local on = active and prevActive
                            line(prevX, prevY, cx, cy, on and (isSelected and 3 or 1.5) or (isSelected and 2 or 1),
                                { c[1], c[2], c[3], on and alpha or (isSelected and 0.4 or 0.15) })
                        end
                        prevX, prevY, prevActive = cx, cy, active
                    end
                end
            end
        end
    end
    -- rychlost: za koncem jízdy (trasa ujetá) křivka nic neřídí; kde jede vozidlo jinak než křivka (konec trasy,
    -- strop couvání), je skutečná rychlost tence bíle
    if selected ~= nil and selected.kind == "speed" and Ch.hasPoints(self:channelOf(selected, false)) then
        local lo, hi = self:channelRange(selected)
        local finish = self:channelFinish(selected)
        if finish ~= nil and self:xAtTime(finish) < gx1 then
            local fx = math.max(self:xAtTime(finish), gx0)
            rect(fx, gy0, gx1 - fx, gy1 - gy0, { 0, 0, 0, 0.5 })
            rect(fx, gy0, 2 * px, gy1 - gy0, ui.endMark)
            text(fx + 0.004, gy1 - 0.02, E.TEXT_SIZE * 0.78, string.format(t_("cine_ch_routeEnd"), finish), ui.endMark, RenderText.ALIGN_LEFT, true)
        end
        local prevX, prevY
        for k = 0, steps do
            local tt = v0 + range * k / steps
            local real = self:actorSpeedAt(selected.owner, tt)
            local cx, cy
            if real ~= nil and math.abs(real - (self:channelValueAt(selected, tt) or 0)) > 1 then
                cx, cy = self:xAtTime(tt), gy0 + (gy1 - gy0) * M.clamp((real - lo) / (hi - lo), 0, 1)
                if prevX ~= nil then
                    line(prevX, prevY, cx, cy, 1.5, { 1, 1, 1, 0.7 })
                end
            end
            prevX, prevY = cx, cy
        end
    end
    -- ovládací body vybraného kanálu
    if selected ~= nil and selected.kind ~= "camspeed" then
        local ch = self:channelOf(selected, false)
        local lo, hi = self:channelRange(selected)
        local delay = self:channelDelay(selected)
        local c = self:channelColor(selected)
        for i, p in ipairs(ch ~= nil and ch.points or {}) do
            local isPoint = self.chPoint ~= nil and self.chPoint.key == selected.key and self.chPoint.index == i
            local x, y = self:xAtTime(p.t + delay), gy0 + (gy1 - gy0) * (p.v - lo) / (hi - lo)
            channelPoint(x, y, p.mode, isPoint and ui.keySelected or ui.key)
            if isPoint then
                text(x, y + 0.014, E.TEXT_SIZE * 0.78, string.format("%.1f %s  %.1f s", p.v, selected.unit or "", p.t + delay), ui.text, RenderText.ALIGN_CENTER, true)
            end
        end
        if not Ch.hasPoints(ch) then
            text((gx0 + gx1) * 0.5, (gy0 + gy1) * 0.5, E.TEXT_SIZE, t_("cine_ch_empty"), ui.dim, RenderText.ALIGN_CENTER)
        end
        local now = self:channelValueAt(selected, self.playhead)
        if now ~= nil then
            text(gx1 - 0.004, gy1 - 0.02, E.TEXT_SIZE * 0.85, string.format("%.1f %s", now, selected.unit or ""), ui.text, RenderText.ALIGN_RIGHT, true)
        end
    end

    -- pruh značek nahoře
    local sy = top + E.CURVE_HEIGHT - E.CH_STRIP_H
    rect(gx0, sy, gx1 - gx0, E.CH_STRIP_H - py, { 0.045, 0.05, 0.06, 1 })
    if selected ~= nil and selected.owner ~= "cam" then
        local a = self.shot.actors[selected.owner]
        for j = 1, #(a.points or {}) do
            local tj = self:routePointTime(selected.owner, j)
            if tj ~= nil then
                local x = self:xAtTime(tj)
                local on = self.topdown ~= nil and self.topdown.point ~= nil and self.topdown.point.actor == selected.owner and self.topdown.point.index == j
                local c = on and ui.keySelected or ui.routeKey
                rect(x - 4 * px, sy + 0.005, 8 * px, 8 * py, c)
                text(x, sy + 0.0155, E.TEXT_SIZE * 0.62, tostring(j), ui.dim, RenderText.ALIGN_CENTER)
            end
        end
    elseif selected ~= nil then
        for _, e in ipairs(S.allKeys(self.shot)) do
            local x = self:xAtTime(e.t)
            rect(x - 4 * px, sy + 0.005, 8 * px, 8 * py, self:selHas("key", e.key) and ui.keySelected or ui.key)
        end
        for _, seg in ipairs(self.shot.segments) do
            for _, m in ipairs(seg.track.marks or {}) do
                local x = self:xAtTime(seg.t + m.u * (seg.track.duration or 0))
                rect(x - 3 * px, sy + 0.006, 6 * px, 6 * py, self:selHas("mark", m) and ui.keySelected or ui.mark)
            end
        end
    end
    local phx = self:xAtTime(self.playhead)
    rect(phx - px * 0.5, top, px, E.CURVE_HEIGHT, ui.playhead)
    setClip(nil)
    text(gx1 - 0.004, sy + 0.007, E.TEXT_SIZE * 0.72, t_(selected ~= nil and selected.kind == "camspeed" and "cine_ch_hintSpeed" or "cine_ch_hint"),
        ui.dim, RenderText.ALIGN_RIGHT)
end

-- Nápověda k tomu, co je pod kurzorem (co udělá klik a tažení), ve volném místě lišty osy mezi levými a pravými tlačítky.
function CinemaEditorScreen:drawStatus()
    local hint = self:hoverHint()
    if hint == nil then
        return
    end
    local x0, x1 = E.BAR_X0, E.BAR_X1
    for _, entry in ipairs(self:toolbarLayout()) do
        if entry.right then
            x1 = math.min(x1, entry.x)
        else
            x0 = math.max(x0, entry.x + entry.w)
        end
    end
    x0, x1 = x0 + E.TOOL_GROUP_GAP, x1 - E.TOOL_GROUP_GAP
    if x1 - x0 < 0.02 then
        return
    end
    local size = E.TEXT_SIZE * 0.8
    local width = getTextWidth(size, hint)
    if width > x1 - x0 then
        size = size * (x1 - x0) / width
    end
    text(x0, self:toolbarY() + E.TOOLBAR_H * 0.5 - size * 0.35, size, hint, E.UI.keyHover, RenderText.ALIGN_LEFT)
end

-- Stav editoru po řádcích pro menu Stav: bloky, ohnisko a let, co se ovládá, režim na ukazateli, rychlosti.
function CinemaEditorScreen:statusLines()
    local shot = self.shot
    local blockText = "-"
    local selSeg, selIndex = self:selectedKey()
    if selSeg ~= nil then
        blockText = string.format(g_i18n:getText("cine_status_keyOf"), selIndex, #selSeg.track.keys)
    elseif #shot.segments > 0 then
        blockText = string.format(g_i18n:getText("cine_status_blocks"), #shot.segments)
    end
    local info = { string.format(g_i18n:getText("cine_status"), blockText, self.targetFocal, self.flySpeed) }
    if self.topdown ~= nil then
        info[#info + 1] = string.format(g_i18n:getText("cine_status_topdown"), self:getActiveTargetText(), self.planHeight or 0)
    elseif #shot.actors > 0 then
        info[#info + 1] = string.format(g_i18n:getText("cine_status_active"), self:getActiveTargetText())
    end
    if shot.env ~= nil then
        info[#info + 1] = string.format(g_i18n:getText("cine_status_env"), CinemaEnvironment.summary(shot.env))
    end
    local playheadSegment = S.segmentAt(shot, self.playhead)
    if playheadSegment ~= nil and playheadSegment.track.mode ~= S.FLIGHT then
        local name = self:targetName(playheadSegment.track.target) or g_i18n:getText("cine_status_missing")
        if playheadSegment.track.target == nil then
            name = "-"
        end
        info[#info + 1] = string.format(g_i18n:getText("cine_status_track"), E.trackLabel(playheadSegment.track), name)
    elseif #shot.focus > 0 then
        local _, current = S.focusAt(shot, self.playhead)
        if current ~= nil and current.target ~= nil then
            info[#info + 1] = string.format(g_i18n:getText("cine_status_lookAt"), self:targetName(current.target) or g_i18n:getText("cine_status_missing"))
        end
    end
    if selSeg ~= nil then
        info[#info + 1] = string.format(g_i18n:getText("cine_status_keySpeed"), (S.keySpeed(shot, selSeg.track, selIndex)))
        info[#info + 1] = string.format(g_i18n:getText("cine_status_pass"),
            g_i18n:getText("cine_pass_" .. S.keyPass(selSeg.track.keys[selIndex])))
    end
    if playheadSegment == nil and #shot.segments > 0 then
        info[#info + 1] = g_i18n:getText("cine_status_hold")
    end
    local camSpeed = self:cameraSpeedAt(self.playhead)
    if camSpeed ~= nil then
        info[#info + 1] = string.format(g_i18n:getText("cine_status_camSpeed"), camSpeed, camSpeed * 3.6)
    end
    for i, a in ipairs(shot.actors) do
        local v = self:actorSpeedAt(i, self.playhead)
        if v ~= nil then
            info[#info + 1] = string.format(g_i18n:getText("cine_status_actorSpeed"), a.name or "?", v)
        end
    end
    if self.picking then
        info[#info + 1] = g_i18n:getText("cine_msg_pick")
    end
    return info
end

function CinemaEditorScreen:drawMessage()
    if self.message == nil or self.messageTimer <= 0 then
        return
    end
    local size = E.TEXT_SIZE * 1.1
    local width = getTextWidth(size, self.message) + 0.02
    local y = self:getPanelTop() + (self.curves and E.CURVE_HEIGHT or 0) + 0.03
    rect(0.5 - width * 0.5, y - 0.008, width, size + 0.016, E.UI.message)
    text(0.5, y, size, self.message, E.UI.text, RenderText.ALIGN_CENTER)
end

E.HELP_SECTIONS = {
    { title = "cine_hs_move", rows = { { "cine_hk_fly", "cine_hd_fly" }, { "cine_hk_vert", "cine_hd_vert" }, { "cine_hk_look", "cine_hd_look" }, { "cine_hk_speed", "cine_hd_speed" }, { "cine_hk_lens", "cine_hd_lens" } } },
    { title = "cine_hs_keys", rows = { { "cine_hk_key", "cine_hd_key" }, { "cine_hk_prevnext", "cine_hd_prevnext" }, { "cine_hk_raise", "cine_hd_raise" }, { "cine_hk_scrub", "cine_hd_scrub" }, { "cine_hk_step", "cine_hd_step" }, { "cine_hk_delete", "cine_hd_delete" }, { "cine_hk_ends", "cine_hd_ends" }, { "cine_hk_play", "cine_hd_play" }, { "cine_hk_blockspeed", "cine_hd_blockspeed" }, { "cine_hk_playtl", "cine_hd_playtl" }, { "cine_hk_curves", "cine_hd_curves" }, { "cine_hk_camline", "cine_hd_camline" } } },
    { title = "cine_hs_blocks", rows = { { "cine_hk_bwheel", "cine_hd_bwheel" }, { "cine_hk_bspeed", "cine_hd_bspeed" }, { "cine_hk_bmenu", "cine_hd_bmenu" }, { "cine_hk_bease", "cine_hd_bease" }, { "cine_hk_blen", "cine_hd_blen" },
        { "cine_hk_pass", "cine_hd_pass" }, { "cine_hk_free", "cine_hd_free" }, { "cine_hk_easeHandle", "cine_hd_easeHandle" }, { "cine_hk_pathHandle", "cine_hd_pathHandle" } } },
    { title = "cine_hs_edit", rows = { { "cine_hk_sel", "cine_hd_sel" }, { "cine_hk_move", "cine_hd_move" }, { "cine_hk_trim", "cine_hd_trim" }, { "cine_hk_part", "cine_hd_part" }, { "cine_hk_copy", "cine_hd_copy" }, { "cine_hk_snap", "cine_hd_snap" }, { "cine_hk_editmode", "cine_hd_editmode" }, { "cine_hk_split", "cine_hd_split" }, { "cine_hk_ripple", "cine_hd_ripple" }, { "cine_hk_clip", "cine_hd_clip" }, { "cine_hk_history", "cine_hd_history" } } },
    { title = "cine_hs_vehicles", rows = { { "cine_hk_pick", "cine_hd_pick" }, { "cine_hk_topdown", "cine_hd_topdown" }, { "cine_hk_tab", "cine_hd_tab" }, { "cine_hk_route", "cine_hd_route" }, { "cine_hk_colour", "cine_hd_colour" }, { "cine_hk_actions", "cine_hd_actions" }, { "cine_hk_detail", "cine_hd_detail" }, { "cine_hk_home", "cine_hd_home" }, { "cine_hk_drop", "cine_hd_drop" }, { "cine_hk_lanes", "cine_hd_lanes" }, { "cine_hk_eye", "cine_hd_eye" }, { "cine_hk_dock", "cine_hd_dock" }, { "cine_hk_cursor", "cine_hd_cursor" } } },
    { title = "cine_hs_shot", rows = { { "cine_hk_shot", "cine_hd_shot" }, { "cine_hk_camera", "cine_hd_camera" }, { "cine_hk_mark", "cine_hd_mark" }, { "cine_hk_shots", "cine_hd_shots" }, { "cine_hk_clean", "cine_hd_clean" }, { "cine_hk_frame", "cine_hd_frame" }, { "cine_hk_undo", "cine_hd_undo" }, { "cine_hk_save", "cine_hd_save" }, { "cine_hk_close", "cine_hd_close" } } },
}

E.HELP_TEXT = 0.9 -- násobek E.TEXT_SIZE pro text nápovědy

-- Zalomení textu do šířky maxWidth (slova zůstávají celá).
local function wrapWords(s, size, maxWidth)
    local lines, line = {}, ""
    for word in s:gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and getTextWidth(size, try) > maxWidth then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then
        lines[#lines + 1] = line
    end
    return lines
end

-- Sekce nápovědy jako řádky { text, x, line (od horního okraje sloupce), barva, tučně } a výška sekce v řádcích.
local function layoutSection(section, size, keyW, descW)
    local rows, line = {}, 0
    rows[#rows + 1] = { text = g_i18n:getText(section.title), x = 0, line = line, color = E.UI.keySelected, bold = true }
    line = line + 1.3
    for _, row in ipairs(section.rows) do
        local label = wrapWords(g_i18n:getText(row[1]), size, keyW)
        local desc = wrapWords(g_i18n:getText(row[2]), size, descW)
        local count = math.max(#label, #desc, 1)
        for k = 1, count do
            if label[k] ~= nil then
                rows[#rows + 1] = { text = label[k], x = 0, line = line + k - 1, color = E.UI.keySelected, bold = false }
            end
            if desc[k] ~= nil then
                rows[#rows + 1] = { text = desc[k], x = keyW, line = line + k - 1, color = E.UI.text, bold = false }
            end
        end
        line = line + count + 0.25
    end
    return rows, line + 0.7
end

-- Sloupce nápovědy (řádky textu) a výška nejvyššího v řádcích.
local function helpColumns(size, keyW, descW)
    local columns, tallest = {}, 0
    for c, group in ipairs({ { 1, 2 }, { 3, 4 }, { 5, 6 } }) do
        local rows, lines = {}, 0
        for _, index in ipairs(group) do
            local sectionRows, height = layoutSection(E.HELP_SECTIONS[index], size, keyW, descW)
            for _, r in ipairs(sectionRows) do
                r.line = r.line + lines
                rows[#rows + 1] = r
            end
            lines = lines + height
        end
        columns[c] = rows
        tallest = math.max(tallest, lines)
    end
    return columns, tallest
end

-- Přes celou obrazovku ve třech sloupcích; když se nevejde, text se zmenší.
function CinemaEditorScreen:drawHelp()
    local x0, colW, gap = 0.03, 0.30, 0.02
    local keyW = 0.1
    local descW = colW - keyW - 0.01
    local size = E.TEXT_SIZE * E.HELP_TEXT
    local top = 0.975
    local titleH = 0.05
    local columns, tallest = helpColumns(size, keyW, descW)
    local room = top - titleH - 0.02
    if tallest * size * 1.5 > room then
        size = size * room / (tallest * size * 1.5)
        columns, tallest = helpColumns(size, keyW, descW)
    end
    local lineH = size * 1.5
    local ui = E.UI
    text(x0, top - 0.03, E.TEXT_SIZE * 1.3, E.upper(g_i18n:getText("cine_help_title")), ui.text, RenderText.ALIGN_LEFT, true)
    text(1 - x0, top - 0.03, E.TEXT_SIZE * 0.9, g_i18n:getText("cine_help_close"), ui.dim, RenderText.ALIGN_RIGHT)
    rect(x0, top - titleH + 0.008, 1 - 2 * x0, 2 * g_pixelSizeScaledY, ui.highlight)
    local base = top - titleH
    for c, rows in ipairs(columns) do
        local cx = x0 + (c - 1) * (colW + gap)
        for _, r in ipairs(rows) do
            text(cx + r.x, base - (r.line + 1) * lineH, size, r.text, r.color, RenderText.ALIGN_LEFT, r.bold)
        end
    end
end
